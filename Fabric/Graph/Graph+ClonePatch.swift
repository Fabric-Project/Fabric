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
/// the node objects and whatever they hold at runtime with them. A node
/// moved or renamed is moved or renamed; a port published, named or given a
/// value is published, named or given it; a sub graph nested in a member is
/// patched the same way inside, its proxies published as the stored graph
/// has them. A node whose entry differs in anything else, its settings, is
/// decoded from the stored entry and put in place of the old one under its
/// ids, as a document load would make it, the inlets it feeds holding what
/// they have until it sends. The sibling's own values, its published
/// inlets', are kept through a replacement.
///
/// A patch is planned before anything is changed, every node it needs
/// decoded first, so a sibling that cannot be patched is left as it was.
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
            let stored: StoredGraph
            do
            {
                guard try self.refreshCloneSetGraphUndoably(from: member) else { return }
                stored = try self.storedGraph(of: member)
            }
            catch
            {
                print("Clone set sync: \(member) could not be stored: \(error.localizedDescription)")
                return
            }

            for sibling in self.cloneSiblings(of: member)
            {
                do { try sibling.graph?.patchCloneMember(sibling, to: stored) }
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
            try target.graph?.patchCloneMember(target, to: try self.storedGraph(of: source))
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

    /// A set's stored graph read once for every sibling patched to it: the
    /// graph as stored, which nodes are decoded from, and the form it is
    /// compared in.
    private struct StoredGraph
    {
        let graph: [String: Any]
        let comparable: [String: Any]
    }

    private func storedGraph(of member: SubgraphNode) throws -> StoredGraph
    {
        guard let setID = member.cloneSetID, let set = self.cloneSet(for: setID) else
        {
            throw recoverableGraphError(.notACloneMember, message: "\(member) is not in a clone set.")
        }
        let graph = set.graphObject
        return StoredGraph(graph: graph, comparable: Self.nonDesignInlets(inGraph: graph).graph)
    }

    /// Patches `member`, a node in this graph, to `stored`, its set's graph.
    private func patchCloneMember(_ member: SubgraphNode, to stored: StoredGraph) throws
    {
        guard let live = CloneSet.jsonObject(from: try Self.cloneSetJSON(of: member.subGraph)) else
        {
            throw recoverableGraphError(.cloneOperationFailed, message: "\(member)'s sub graph could not be encoded for its clone set.")
        }
        let patch = try member.subGraph.plan(from: Self.nonDesignInlets(inGraph: live).graph,
                                             to: stored.comparable,
                                             stored: stored.graph)

        // A node put in another's place decodes with the source's values on
        // the inlets that are the member's own; those go back on, on the
        // ports made again and nowhere else.
        let ownInlets = member.subGraph.memberOwnInlets()
        let ownValues = ownInlets.mapValues { (portType: $0.portType, value: $0.snapshotValue()) }
        member.subGraph.apply(patch)
        for (path, port) in member.subGraph.memberOwnInlets() where ownInlets[path] !== port
        {
            guard let saved = ownValues[path], saved.portType == port.portType else { continue }
            port.restoreValue(from: saved.value)
        }
    }

    // MARK: Planning

    /// What brings one graph to its stored form, decided and decoded before
    /// anything is changed.
    private struct GraphPatch
    {
        let to: [String: Any]
        var deletions: [Node] = []
        var additions: [Node] = []
        var placements: [(node: Node, value: [String: Any])] = []
        var replacements: [(existing: Node, replacement: Node)] = []
        var nested: [(graph: Graph, patch: GraphPatch)] = []
        /// Each proxy's id and publishing in this graph, by its inner port's id.
        var proxyStates: [(node: SubgraphNode, states: [UUID: ProxyEntry])] = []
        var portStates: [(node: Node, states: [UUID: PortState])] = []
        var order: [UUID] = []
    }

    private struct PublishedState: Equatable
    {
        let published: Bool
        let publishedName: String?

        init?(_ base: [String: Any])
        {
            guard let published = base["published"] as? Bool else { return nil }
            self.published = published
            self.publishedName = base["publishedName"] as? String
        }
    }

    private struct ProxyEntry
    {
        let id: UUID
        let publishing: PublishedState
    }

    /// What a port takes in place: its publishing, and the value it holds
    /// where that is design (see Graph.nonDesignInlets).
    private struct PortState
    {
        let publishing: PublishedState
        let value: PortValue??
    }

    /// The keys a port entry changes without its node being made again.
    private static let portStateKeys: Set<String> = ["published", "publishedName", "value"]

    /// A port entry's bytes without its state, for telling a change in its
    /// state from one in what it is. A parameter's label follows the port's
    /// published name (see rebuildPublishedParameterGroup), so it is state.
    private static func comparable(ofPort entry: [String: Any], withoutState: Bool) -> Data
    {
        guard withoutState,
              var payload = entry["payload"] as? [String: Any],
              var base = payload["base"] as? [String: Any]
        else { return CloneSet.canonicalJSON(entry) }
        for key in portStateKeys { base[key] = nil }
        if var parameter = base["parameter"] as? [String: Any], var parameterBase = parameter["base"] as? [String: Any]
        {
            parameterBase["value"] = nil
            parameterBase["label"] = nil
            parameter["base"] = parameterBase
            base["parameter"] = parameter
        }
        payload["base"] = base
        var entry = entry
        entry["payload"] = payload
        return CloneSet.canonicalJSON(entry)
    }

    /// The value a port's entry holds, on the port or in its parameter.
    private static func encodedValue(in base: [String: Any]?) -> Data
    {
        let value = base?["value"] ?? ((base?["parameter"] as? [String: Any])?["base"] as? [String: Any])?["value"]
        return CloneSet.canonicalJSON(["value": value ?? NSNull()])
    }

    private static func portEntries(in value: [String: Any]) -> [UUID: [String: Any]]
    {
        var entries: [UUID: [String: Any]] = [:]
        for entry in value["ports"] as? [[String: Any]] ?? []
        {
            guard let base = (entry["payload"] as? [String: Any])?["base"] as? [String: Any],
                  let id = (base["id"] as? String).flatMap(UUID.init(uuidString:))
            else { continue }
            entries[id] = entry
        }
        return entries
    }

    /// The states `node`'s ports take to match `entry`'s, nil where a port
    /// differs in more than its state, or the port set differs.
    private static func portStates(of node: Node, from before: NodeEntry, to entry: NodeEntry) -> [UUID: PortState]?
    {
        let fromPorts = portEntries(in: before.value)
        let toPorts = portEntries(in: entry.value)
        guard Set(fromPorts.keys) == Set(toPorts.keys) else { return nil }

        var states: [UUID: PortState] = [:]
        for (id, toPort) in toPorts
        {
            guard let fromPort = fromPorts[id], CloneSet.canonicalJSON(fromPort) != CloneSet.canonicalJSON(toPort) else { continue }
            guard comparable(ofPort: fromPort, withoutState: true) == comparable(ofPort: toPort, withoutState: true),
                  let payload = toPort["payload"] as? [String: Any],
                  let base = payload["base"] as? [String: Any],
                  let publishing = PublishedState(base),
                  node.ports.contains(where: { $0.id == id })
            else { return nil }

            var value: PortValue?? = nil
            let fromBase = (fromPort["payload"] as? [String: Any])?["base"] as? [String: Any]
            if Self.encodedValue(in: base) != Self.encodedValue(in: fromBase)
            {
                guard let data = try? JSONSerialization.data(withJSONObject: payload),
                      let port = try? JSONDecoder().decode(AnyPort.self, from: data)
                else { return nil }
                value = .some(port.base.snapshotValue())
            }
            states[id] = PortState(publishing: publishing, value: value)
        }
        return states
    }

    private static func proxyStates(in value: [String: Any]) -> [UUID: ProxyEntry]
    {
        var states: [UUID: ProxyEntry] = [:]
        for entry in value["proxyPorts"] as? [[String: Any]] ?? []
        {
            guard let base = entry["base"] as? [String: Any],
                  let id = (base["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let innerPortID = (base["innerPortID"] as? String).flatMap(UUID.init(uuidString:)),
                  let publishing = PublishedState(base)
            else { continue }
            states[innerPortID] = ProxyEntry(id: id, publishing: publishing)
        }
        return states
    }

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

    /// Plans the patch that brings this graph from `from`, its encoding as a
    /// set stores one, to `to`, both with the values that are not design
    /// left out. `stored` is `to` with them in, which a node is decoded from.
    private func plan(from: [String: Any], to: [String: Any], stored: [String: Any]) throws -> GraphPatch
    {
        var patch = GraphPatch(to: to)
        let fromEntries = Self.nodeEntries(in: from)
        let toEntries = Self.nodeEntries(in: to)
        let fromByID = Dictionary(fromEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let toIDs = Set(toEntries.map(\.id))
        let storedByID = Dictionary(Self.nodeEntries(in: stored).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for entry in fromEntries where !toIDs.contains(entry.id)
        {
            self.node(forID: entry.id).map { patch.deletions.append($0) }
        }

        for entry in toEntries
        {
            guard let storedEntry = storedByID[entry.id] else { continue }
            guard let before = fromByID[entry.id], let node = self.node(forID: entry.id) else
            {
                patch.additions.append(try self.decodeStoredNode(storedEntry))
                continue
            }
            guard before.comparable != entry.comparable else { continue }

            if before.comparable(without: Self.placementKeys) == entry.comparable(without: Self.placementKeys)
            {
                patch.placements.append((node, entry.value))
                continue
            }

            // A sub graph nested in the member is patched inside, where what
            // differs is inside it, or in how its proxies are published here.
            // A nested member's inside is its own set's; only its proxies are.
            let subGraphKeys = Self.placementKeys.union(["subGraph", "proxyPorts"])
            if let nested = node as? SubgraphNode,
               before.comparable(without: subGraphKeys) == entry.comparable(without: subGraphKeys)
            {
                patch.placements.append((node, entry.value))
                if nested.cloneSetID == nil,
                   let fromSubGraph = before.value["subGraph"] as? [String: Any],
                   let toSubGraph = entry.value["subGraph"] as? [String: Any],
                   let storedSubGraph = storedEntry.value["subGraph"] as? [String: Any]
                {
                    patch.nested.append((nested.subGraph, try nested.subGraph.plan(from: fromSubGraph, to: toSubGraph, stored: storedSubGraph)))
                }
                patch.proxyStates.append((nested, Self.proxyStates(in: entry.value)))
                continue
            }

            // A port published, named or given a value takes it in place.
            let portKeys = Self.placementKeys.union(["ports"])
            if before.comparable(without: portKeys) == entry.comparable(without: portKeys),
               let states = Self.portStates(of: node, from: before, to: entry)
            {
                patch.placements.append((node, entry.value))
                patch.portStates.append((node, states))
                continue
            }

            patch.replacements.append((node, try self.decodeStoredNode(storedEntry)))
        }

        patch.order = toEntries.map(\.id)
        return patch
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

    // MARK: Applying

    private func apply(_ patch: GraphPatch)
    {
        for node in patch.deletions { self.delete(node: node) }
        for node in patch.additions { self.addNode(node) }
        for (node, value) in patch.placements { self.place(node, as: value) }
        for (existing, replacement) in patch.replacements { self.replace(existing, with: replacement) }
        for (graph, nested) in patch.nested { graph.apply(nested) }
        for (node, states) in patch.proxyStates { self.publishProxies(of: node, as: states) }
        for (node, states) in patch.portStates { self.setPorts(of: node, to: states) }
        self.reorderNodes(toMatch: patch.order)
        self.patchWires(to: patch.to)
        self.patchNotes(to: patch.to)
    }

    /// Puts `node`'s proxies in this graph under the ids `states` has for
    /// them and publishes them as it has them, by inner port id: the proxies
    /// stand after the inside is patched. A nested member's proxies take ids
    /// of their own, and every instance of it holds them under the same ones.
    private func publishProxies(of node: SubgraphNode, as states: [UUID: ProxyEntry])
    {
        node.remakeProxies(withIDs: states.mapValues(\.id))
        for proxy in node.ports
        {
            guard let innerPortID = (proxy as? any ProxyPortProtocol)?.innerPortID, let state = states[innerPortID] else { continue }
            self.publish(proxy, as: state.publishing)
        }
    }

    private func setPorts(of node: Node, to states: [UUID: PortState])
    {
        for port in node.ports
        {
            guard let state = states[port.id] else { continue }
            if case .some(let value) = state.value { self.setValue(value, of: port) }
            self.publish(port, as: state.publishing)
        }
    }

    private func publish(_ port: Port, as state: PublishedState)
    {
        if port.published != state.published { self.setPublished(state.published, on: port) }
        if port.publishedName != state.publishedName { self.setPublishedName(state.publishedName, on: port) }
    }

    /// `port`'s value, set as a sync sets it: a port of a node in this graph.
    private func setValue(_ value: PortValue?, of port: Port)
    {
        let previous = port.snapshotValue()
        port.restoreValue(from: value)

        let portID = port.id
        self.registerUndo { graph in
            graph.nodePort(forID: portID).map { graph.setValue(previous, of: $0) }
        }
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
    /// where `existing` stood. The wires on `existing` stay, bound to the
    /// replacement's ports where it has them and dropped where it does not;
    /// its inlets take what the outlets feeding them hold, and the inlets it
    /// fed keep what they hold until the replacement sends; what the proxies
    /// standing for its published ports hold up the chain (see
    /// ProxyChainState) is put back where the replacement can take it. One undo step, which holds `existing` and puts it back the
    /// same way with what it held, the wires onto ports the replacement
    /// does not have included.
    private func replace(_ existing: Node,
                         with replacement: Node,
                         proxyChains carriedChains: [UUID: ProxyChainState]? = nil,
                         wires carriedWires: [Wire] = [])
    {
        let order = self.nodes.map(\.id)
        let droppedPortIDs = Set(existing.ports.map(\.id)).subtracting(replacement.ports.map(\.id))
        let droppedWires = self.connections
            .filter { droppedPortIDs.contains($0.outletPortID) || droppedPortIDs.contains($0.inletPortID) }
            .map(Wire.init)
        var proxyChains: [UUID: ProxyChainState] = [:]
        for port in existing.ports where port.published
        {
            proxyChains[port.id] = self.proxyChainState(standingFor: port)
        }

        self.withoutUndoRegistration {
            self.delete(node: existing, disconnect: false)
            self.addNode(replacement)
            self.reorderNodes(toMatch: order)
            self.reattachConnections(to: replacement.ports, replacementsSend: false)
            self.pruneDanglingConnections()
            for wire in carriedWires { self.restore(wire) }
            for (portID, chain) in carriedChains ?? proxyChains
            {
                guard let port = replacement.ports.first(where: { $0.id == portID }), port.published else { continue }
                self.restoreProxyChain(standingFor: port, to: chain)
            }
            // Onto a proxy a port the replacement does not have had, up the chain.
            for graph in self.ancestors { graph.pruneDanglingConnections() }
        }

        let id = existing.id
        self.registerUndo { graph in
            guard let current = graph.node(forID: id) else { return }
            graph.replace(current, with: existing, proxyChains: proxyChains, wires: droppedWires)
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

    private func patchNotes(to: [String: Any])
    {
        let toNotes = Self.notes(in: to)
        let toIDs = Set(toNotes.map(\.id))
        for note in self.notes where !toIDs.contains(note.id)
        {
            self.deleteNote(note)
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
