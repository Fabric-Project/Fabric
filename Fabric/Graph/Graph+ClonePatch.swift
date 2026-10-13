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
/// has them. What else a node's entry differs in is its settings, which the
/// node takes from the stored entry through Graph.setSettings, keeping its
/// object, its runtime state and the ports the settings leave; a port the
/// settings add takes the id, value and publishing the stored graph has for
/// it. The sibling's own values, its published inlets', are kept.
///
/// A patch is planned before anything is changed, every node and settings
/// value it needs decoded first, so a sibling that cannot be patched is left
/// as it was.
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
    internal func refreshCloneSetGraphUndoably(from member: SubgraphNode) throws -> Bool
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

        // A port a settings change makes again takes the stored graph's
        // value, the source member's; on an inlet that is the member's own,
        // the member's goes back on, on the ports made again and nowhere else.
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
        var settings: [SettingsChange] = []
        /// A nested sub graph's clone set, where it joins or leaves one.
        var memberships: [(node: SubgraphNode, setID: UUID?)] = []
        var nested: [(graph: Graph, patch: GraphPatch)] = []
        /// Each proxy's id and publishing in this graph, by its inner port's id.
        var proxyStates: [(node: SubgraphNode, states: [UUID: ProxyEntry])] = []
        var portPatches: [(node: Node, patches: [UUID: PortPatch])] = []
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
    private struct PortPatch
    {
        let publishing: PublishedState
        let value: PortValue??
    }

    /// A node's settings as its stored entry holds them, and the state of
    /// each port the stored entry holds under a registry key the node has
    /// no port under: what a port the settings add takes, its id first, for
    /// the wires and proxies the stored graph names it by.
    private struct SettingsChange
    {
        let node: Node
        let settings: any NodeSettings
        let addedPorts: [PortState]
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

    /// What a node's ports take in place to bring it from `before` to
    /// `entry`: each port both entries hold takes its publishing and, where
    /// that differs as design, its value. A port only one of them holds is
    /// the node's settings' to add or take away.
    private static func portPatches(from before: NodeEntry, to entry: NodeEntry) -> [UUID: PortPatch]
    {
        let fromPorts = portEntries(in: before.value)
        var patches: [UUID: PortPatch] = [:]
        for (id, toPort) in portEntries(in: entry.value)
        {
            guard let fromPort = fromPorts[id], CloneSet.canonicalJSON(fromPort) != CloneSet.canonicalJSON(toPort),
                  let payload = toPort["payload"] as? [String: Any],
                  let base = payload["base"] as? [String: Any],
                  let publishing = PublishedState(base)
            else { continue }

            var value: PortValue?? = nil
            let fromBase = (fromPort["payload"] as? [String: Any])?["base"] as? [String: Any]
            if Self.encodedValue(in: base) != Self.encodedValue(in: fromBase),
               let data = try? JSONSerialization.data(withJSONObject: payload),
               let port = try? JSONDecoder().decode(AnyPort.self, from: data)
            {
                value = .some(port.base.snapshotValue())
            }
            patches[id] = PortPatch(publishing: publishing, value: value)
        }
        return patches
    }

    /// The settings `entry`, a node's stored entry, holds for `node`, nil
    /// where the node has none or holds them already. A node's settings are
    /// written flattened into its own entry, so the entry decodes as the
    /// node's own settings type.
    private func storedSettings(of node: Node, in entry: NodeEntry) throws -> (any NodeSettings)?
    {
        guard let current = node.settings else { return nil }
        let stored: any NodeSettings
        do
        {
            let data = try JSONSerialization.data(withJSONObject: entry.value)
            stored = try Self.decodeSettings(like: current, from: data)
        }
        catch
        {
            throw recoverableGraphError(.cloneOperationFailed, message: "The settings of \(node) in the stored graph could not be read: \(error.localizedDescription)")
        }
        return stored.isEqual(to: current) ? nil : stored
    }

    private static func decodeSettings<Settings: NodeSettings>(like current: Settings, from data: Data) throws -> any NodeSettings
    {
        try JSONDecoder().decode(Settings.self, from: data)
    }

    /// The state of each port `entry` holds under a registry key `node` has
    /// no port under; see SettingsChange.
    private static func addedPortStates(of node: Node, in entry: NodeEntry) -> [PortState]
    {
        let present = Set(node.registry.portStates().map(\.registryKey))
        return (entry.value["ports"] as? [Any] ?? []).compactMap { snapshot in
            guard let data = try? JSONSerialization.data(withJSONObject: snapshot),
                  let snapshot = try? JSONDecoder().decode(PortRegistry.Snapshot.self, from: data),
                  !present.contains(snapshot.name)
            else { return nil }
            return PortState(of: snapshot.payload.base, registryKey: snapshot.name)
        }
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
        /// keys alone from one in anything else.
        func comparable(without keys: Set<String>) -> Data
        {
            CloneSet.canonicalJSON(["type": type, "value": value.filter { !keys.contains($0.key) }])
        }
    }

    private static func nodeEntries(in graph: [String: Any]) -> [NodeEntry]
    {
        (graph["nodeMap"] as? [Any] ?? []).compactMap(NodeEntry.init)
    }

    /// The keys a node's placement changes in its entry.
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

            patch.placements.append((node, entry.value))
            if before.comparable(without: Self.placementKeys) == entry.comparable(without: Self.placementKeys) { continue }

            // A sub graph nested in the member joins or leaves a set as the
            // stored graph has it, is patched inside, and has its proxies here
            // published as the stored graph has them. A nested member's inside
            // is its own set's; only its proxies are this one's.
            if let nested = node as? SubgraphNode
            {
                let storedSetID = (entry.value[Self.cloneSetIDKey] as? String).flatMap(UUID.init(uuidString:))
                if nested.cloneSetID != storedSetID { patch.memberships.append((nested, storedSetID)) }
                if nested.cloneSetID == nil,
                   let fromSubGraph = before.value["subGraph"] as? [String: Any],
                   let toSubGraph = entry.value["subGraph"] as? [String: Any],
                   let storedSubGraph = storedEntry.value["subGraph"] as? [String: Any]
                {
                    patch.nested.append((nested.subGraph, try nested.subGraph.plan(from: fromSubGraph, to: toSubGraph, stored: storedSubGraph)))
                }
                patch.proxyStates.append((nested, Self.proxyStates(in: entry.value)))
            }

            // What differs besides is the node's settings and its ports'
            // state, both taken in place.
            if let settings = try self.storedSettings(of: node, in: storedEntry)
            {
                patch.settings.append(SettingsChange(node: node, settings: settings,
                                                     addedPorts: Self.addedPortStates(of: node, in: storedEntry)))
            }
            let portPatches = Self.portPatches(from: before, to: entry)
            if !portPatches.isEmpty { patch.portPatches.append((node, portPatches)) }
        }

        patch.order = toEntries.map(\.id)
        return patch
    }

    /// A node the patch adds, decoded from its stored entry as a document
    /// would decode it, the graphs inside it under fresh ids: the editor and
    /// the renderer cache by graph id, and every instance of a stored graph
    /// has graph ids of its own.
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
        for change in patch.settings { self.setSettings(change.settings, on: change.node, addingPortsAs: change.addedPorts) }
        for (node, setID) in patch.memberships
        {
            let previous = node.cloneSetID
            self.setCloneMembership(setID: setID, on: node)
            self.cloneSetMembershipChanged(setID: previous)
            self.cloneSetMembershipChanged(setID: setID)
        }
        for (graph, nested) in patch.nested { graph.apply(nested) }
        for (node, states) in patch.proxyStates { self.publishProxies(of: node, as: states) }
        for (node, patches) in patch.portPatches { self.setPorts(of: node, to: patches) }
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

    private func setPorts(of node: Node, to patches: [UUID: PortPatch])
    {
        for port in node.ports
        {
            guard let patch = patches[port.id] else { continue }
            if case .some(let value) = patch.value { self.setValue(value, of: port) }
            self.publish(port, as: patch.publishing)
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
    /// rather than the encoding patched from: a node deleted, or a port its
    /// settings took away, took its wires with it, and a proxy a plain nested
    /// sub graph makes carries its inner port's id, so a wire onto it can
    /// read as one onto the node the port had before.
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
