//
//  Graph+ClonePatch.swift
//  Fabric
//
//  Created by Claude on 10/11/26.
//

import Foundation
internal import AnyCodable

/// Keeping a clone set in step: the member edited last is encoded as the
/// set's stored graph, and each sibling is patched to it. The sibling's sub
/// graph is encoded the same way, and the two encodings are compared by id,
/// node entry by node entry, wire by wire, note by note, with the values that
/// are not design left out of the comparison (see Graph.nonDesignInlets).
/// What differs is changed on the live sibling; what matches is left alone,
/// the node objects and whatever they hold at runtime with them. A node whose
/// entry differs is decoded from the stored entry and put in place of the
/// old one under its ids, as a document load would make it; a node moved or
/// renamed is moved or renamed; a plain sub graph nested in a member is
/// patched the same way inside. The sibling's own values, its published
/// inlets', are kept through a replacement.
///
/// Every change registers its own undo step into the edit's open group, so
/// undo and redo put the siblings back with the edit and sync nothing. With
/// no undo group open, a sync registers nothing.
extension Graph
{
    /// How the coordinator brings a member's siblings in line with it.
    internal func syncCloneSiblings(of member: SubgraphNode)
    {
        self.patchCloneSiblings(of: member)
    }

    /// Stores `member`'s sub graph as its set's graph and, where that changed
    /// the stored graph, patches every sibling to it, undoably where an undo
    /// group is open. A sibling that cannot be patched keeps what it has and
    /// is reported.
    public func patchCloneSiblings(of member: SubgraphNode)
    {
        guard member.cloneSetID != nil, !self.cloneSetCoordinator.isSyncing else { return }

        self.whileSyncingClones {
            do
            {
                guard try self.refreshCloneSetGraphUndoably(from: member) else { return }
            }
            catch
            {
                print("Clone set sync: \(member) could not be stored: \(error.localizedDescription)")
                return
            }

            for sibling in self.cloneSiblings(of: member)
            {
                do { try sibling.graph?.patchCloneMember(sibling) }
                catch { print("Clone set sync: \(sibling) not patched from \(member): \(error.localizedDescription)") }
            }
        }
    }

    /// Patches `target` to `source`'s sub graph now, whether or not the stored
    /// graph changed, undoably where an undo group is open. Throws where the
    /// two are not members of one set.
    internal func patchCloneMember(_ target: SubgraphNode, from source: SubgraphNode) throws
    {
        guard let setID = source.cloneSetID, target.cloneSetID == setID, target !== source else
        {
            throw recoverableGraphError(.notACloneMember, message: "\(target) and \(source) are not members of one clone set.")
        }

        try self.whileSyncingClones {
            try self.refreshCloneSetGraphUndoably(from: source)
            try target.graph?.patchCloneMember(target)
        }
    }

    /// Runs `body` as a sync, its writes not taken for edits, and leaves the
    /// edit's undo group with the edit's name. With no undo group open,
    /// nothing it does is registered: an undo step registered then would open
    /// a group of its own and stand apart from the edit.
    private func whileSyncingClones<Result>(_ body: () throws -> Result) rethrows -> Result
    {
        let coordinator = self.cloneSetCoordinator
        let wasSyncing = coordinator.isSyncing
        coordinator.isSyncing = true
        defer { coordinator.isSyncing = wasSyncing }

        guard let undoManager = self.effectiveUndoManager,
              undoManager.groupingLevel > 0, undoManager.isUndoRegistrationEnabled
        else { return try self.withoutUndoRegistration(body) }

        let actionName = undoManager.undoActionName
        defer { if undoManager.undoActionName != actionName { undoManager.setActionName(actionName) } }
        return try body()
    }

    /// refreshCloneSetGraph, with a step that puts the stored graph back.
    @discardableResult
    private func refreshCloneSetGraphUndoably(from member: SubgraphNode) throws -> Bool
    {
        guard let setID = member.cloneSetID, let set = self.cloneSet(for: setID) else
        {
            throw recoverableGraphError(.notACloneMember, message: "\(member) is not in a clone set.")
        }
        let previous = set.graphJSON
        guard try self.refreshCloneSetGraph(from: member) else { return false }
        self.registerCloneSetGraphRestore(setID, to: previous)
        return true
    }

    private func registerCloneSetGraphRestore(_ setID: UUID, to graphJSON: Data)
    {
        self.registerUndo { graph in
            guard let set = graph.cloneSet(for: setID) else { return }
            let current = set.graphJSON
            set.graphJSON = graphJSON
            graph.registerCloneSetGraphRestore(setID, to: current)
        }
    }

    // MARK: - Patching a member

    /// Patches `member`, a node in this graph, to its set's stored graph.
    private func patchCloneMember(_ member: SubgraphNode) throws
    {
        guard let setID = member.cloneSetID, let set = self.cloneSet(for: setID) else
        {
            throw recoverableGraphError(.notACloneMember, message: "\(member) is not in a clone set.")
        }
        guard let live = CloneSet.jsonObject(from: try Self.cloneSetJSON(of: member.subGraph)) else
        {
            throw recoverableGraphError(.cloneOperationFailed, message: "\(member)'s sub graph could not be encoded for its clone set.")
        }
        let stored = set.graphObject

        // A node put in its place decodes with the source's values; the
        // member's own go back on afterwards.
        let ownValues = member.subGraph.memberOwnInlets().mapValues { (portType: $0.portType, value: $0.snapshotValue()) }
        try member.subGraph.patch(from: Self.nonDesignInlets(inGraph: live).graph,
                                  to: Self.nonDesignInlets(inGraph: stored).graph,
                                  stored: stored)
        SubgraphNode.restore(values: ownValues, in: member.subGraph)
    }

    /// Changes this graph from `from`, its encoding as a set stores one, to
    /// `to`, both with the values that are not design left out. `stored` is
    /// `to` with them in, which a node is decoded from.
    private func patch(from: [String: Any], to: [String: Any], stored: [String: Any]) throws
    {
        try self.patchNodes(from: from, to: to, stored: stored)
        self.patchWires(to: to)
        self.patchNotes(from: from, to: to)
    }

    // MARK: Nodes

    /// A node's entry in an encoded graph: the id it is compared under and
    /// the bytes it is compared by.
    private struct NodeEntry
    {
        let id: UUID
        let type: String
        let value: [String: Any]
        let comparable: Data

        init?(_ entry: Any)
        {
            guard let entry = entry as? [String: Any],
                  let type = entry["type"] as? String,
                  let value = entry["value"] as? [String: Any],
                  let id = (value["id"] as? String).flatMap(UUID.init(uuidString:))
            else { return nil }
            self.id = id
            self.type = type
            self.value = value
            self.comparable = CloneSet.canonicalJSON(entry)
        }

        /// The entry's bytes without `keys`, for telling a change in those
        /// keys alone from one that needs the node made again.
        func comparable(without keys: Set<String>) -> Data
        {
            CloneSet.canonicalJSON(["type": type, "value": value.filter { !keys.contains($0.key) }])
        }
    }

    private static func nodeEntries(in graph: [String: Any]) -> [NodeEntry]
    {
        (graph["nodeMap"] as? [Any] ?? []).compactMap(NodeEntry.init)
    }

    /// The keys a node entry changes without the node being made again.
    private static let placementKeys: Set<String> = ["nodeOffset", "userName"]

    private func patchNodes(from: [String: Any], to: [String: Any], stored: [String: Any]) throws
    {
        let fromEntries = Self.nodeEntries(in: from)
        let toEntries = Self.nodeEntries(in: to)
        let fromByID = Dictionary(fromEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let toIDs = Set(toEntries.map(\.id))
        let storedByID = Dictionary(Self.nodeEntries(in: stored).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for entry in fromEntries where !toIDs.contains(entry.id)
        {
            guard let node = self.node(forID: entry.id) else { continue }
            self.delete(node: node)
        }

        for entry in toEntries
        {
            guard let storedEntry = storedByID[entry.id] else { continue }
            guard let before = fromByID[entry.id], let node = self.node(forID: entry.id) else
            {
                self.addNode(try self.decodeStoredNode(storedEntry))
                continue
            }
            guard before.comparable != entry.comparable else { continue }

            self.place(node, as: entry.value)
            if before.comparable(without: Self.placementKeys) == entry.comparable(without: Self.placementKeys) { continue }

            // A plain sub graph nested in the member is patched inside, where
            // what differs is inside it alone.
            let subGraphKeys = Self.placementKeys.union(["subGraph"])
            if let nested = node as? SubgraphNode, nested.cloneSetID == nil,
               let fromSubGraph = before.value["subGraph"] as? [String: Any],
               let toSubGraph = entry.value["subGraph"] as? [String: Any],
               let storedSubGraph = storedEntry.value["subGraph"] as? [String: Any],
               before.comparable(without: subGraphKeys) == entry.comparable(without: subGraphKeys)
            {
                try nested.subGraph.patch(from: fromSubGraph, to: toSubGraph, stored: storedSubGraph)
                continue
            }

            self.replace(node, with: try self.decodeStoredNode(storedEntry))
        }

        self.reorderNodes(toMatch: toEntries.map(\.id))
    }

    /// A node decoded from its stored entry, as a document would decode it,
    /// the graphs inside it under fresh ids: the editor and the renderer
    /// cache by graph id, and every instance of a stored graph has graph ids
    /// of its own.
    private func decodeStoredNode(_ entry: NodeEntry) throws -> Node
    {
        let value = Self.withGraphIDs(in: entry.value) { UUID().uuidString } as? [String: Any] ?? entry.value
        guard let node = self.decodeNode(from: AnyCodableMap(type: entry.type, value: AnyCodable(value))) else
        {
            throw recoverableGraphError(.cloneOperationFailed, message: "A \(entry.type) in the stored graph could not be decoded.")
        }
        return node
    }

    /// Moves and renames `node` as `value`, its entry, has it, undoably.
    private func place(_ node: Node, as value: [String: Any])
    {
        if let offset = value["nodeOffset"].flatMap(Self.size(from:)), offset != node.offset
        {
            self.registerOffsetChange(of: node, from: node.offset)
            node.offset = offset
        }
        let userName = value["userName"] as? String
        if userName != node.userName
        {
            self.setUserName(userName, of: node)
        }
    }

    /// CGSize as a node's offset encodes it: a pair of numbers, each read
    /// as the integer or the double the JSON parse made of it.
    private static func size(from value: Any) -> CGSize?
    {
        guard let pair = (value as? [Any])?.compactMap({ ($0 as? NSNumber)?.doubleValue }), pair.count == 2 else { return nil }
        return CGSize(width: pair[0], height: pair[1])
    }

    private func setUserName(_ name: String?, of node: Node)
    {
        let previous = node.userName
        guard previous != name else { return }
        node.userName = name
        self.registerUndo(on: node) { node in
            node.graph?.setUserName(previous, of: node)
        }
    }

    /// Puts `replacement`, a node made under `existing`'s ids, in its place,
    /// where `existing` stood, carrying over each wire on `existing` and what
    /// the proxies standing for its published ports hold up the chain (see
    /// ProxyChainState) where the replacement can take them. One undo step,
    /// which holds `existing` and puts it back the same way with what it
    /// held: a deletion and an addition as two steps would lose the proxies'
    /// publishing between them.
    private func replace(_ existing: Node, with replacement: Node,
                         wires carried: [Wire]? = nil, proxyChains carriedChains: [UUID: ProxyChainState]? = nil)
    {
        let order = self.nodes.map(\.id)
        let portIDs = Set(existing.ports.map(\.id))
        let wires = self.connections.filter { portIDs.contains($0.outletPortID) || portIDs.contains($0.inletPortID) }.map(Wire.init)
        var proxyChains: [UUID: ProxyChainState] = [:]
        for port in existing.ports where port.published
        {
            proxyChains[port.id] = self.proxyChainState(standingFor: port)
        }

        self.withoutUndoRegistration {
            self.delete(node: existing)
            self.addNode(replacement)
            self.reorderNodes(toMatch: order)
            for wire in carried ?? wires { self.restore(wire) }
            for (portID, chain) in carriedChains ?? proxyChains
            {
                guard let port = replacement.ports.first(where: { $0.id == portID }), port.published else { continue }
                self.restoreProxyChain(standingFor: port, to: chain)
            }
        }

        let id = existing.id
        self.registerUndo { graph in
            guard let current = graph.node(forID: id) else { return }
            graph.replace(current, with: existing, wires: wires, proxyChains: proxyChains)
        }
    }

    // MARK: Wires

    private struct WireEnds: Hashable
    {
        let outletPortID: UUID
        let inletPortID: UUID
    }

    private static func wires(in graph: [String: Any]) -> [WireEnds: Wire]
    {
        var wires: [WireEnds: Wire] = [:]
        for entry in graph["connections"] as? [[String: Any]] ?? []
        {
            guard let id = (entry["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let outletPortID = (entry["outletPortID"] as? String).flatMap(UUID.init(uuidString:)),
                  let inletPortID = (entry["inletPortID"] as? String).flatMap(UUID.init(uuidString:))
            else { continue }
            let ends = WireEnds(outletPortID: outletPortID, inletPortID: inletPortID)
            wires[ends] = Wire(id: id, outletPortID: outletPortID, inletPortID: inletPortID,
                               active: entry["active"] as? Bool ?? true)
        }
        return wires
    }

    /// Brings the wires to `to`'s, compared against the wires there now
    /// rather than the encoding patched from: a node put aside took its
    /// wires with it, and a proxy a plain nested sub graph makes carries its
    /// inner port's id, so a wire onto it can read as one onto the node the
    /// port had before.
    private func patchWires(to: [String: Any])
    {
        let toWires = Self.wires(in: to)
        let liveWires = Dictionary(self.connections.map { (WireEnds(outletPortID: $0.outletPortID, inletPortID: $0.inletPortID), $0) },
                                   uniquingKeysWith: { first, _ in first })

        for (ends, connection) in liveWires where toWires[ends] == nil
        {
            _ = self.disconnect(connection)
        }
        for (ends, wire) in toWires
        {
            if let connection = liveWires[ends]
            {
                if connection.active != wire.active { _ = self.setConnection(connection, active: wire.active) }
            }
            else
            {
                self.restore(wire)
            }
        }
    }

    // MARK: Notes

    private static func notes(in graph: [String: Any]) -> [Note]
    {
        (graph["notes"] as? [Any] ?? []).compactMap { entry in
            guard let data = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return try? JSONDecoder().decode(Note.self, from: data)
        }
    }

    private func patchNotes(from: [String: Any], to: [String: Any])
    {
        let toNotes = Self.notes(in: to)
        let toIDs = Set(toNotes.map(\.id))
        for note in Self.notes(in: from) where !toIDs.contains(note.id)
        {
            self.notes.first { $0.id == note.id }.map(self.deleteNote)
        }
        for note in toNotes
        {
            guard let live = self.notes.first(where: { $0.id == note.id }) else
            {
                self.addNote(note)
                continue
            }
            guard live.note != note.note || live.rect != note.rect else { continue }
            let previousText = live.note
            let previousRect = live.rect
            live.note = note.note
            live.rect = note.rect
            self.registerNoteEdit(live, previousText: previousText, previousRect: previousRect)
        }
        self.reorderNotes(toMatch: toNotes.map(\.id))
    }
}
