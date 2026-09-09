//
//  Graph+CloneReconcile.swift
//  Fabric
//
//  Created by Claude on 9/10/26.
//

import Foundation
internal import AnyCodable

/// What one reconcile pass changed on the target, summed over nested graphs.
public struct CloneReconcileReport: Equatable
{
    public var nodesAdded = 0
    public var nodesRemoved = 0
    public var nodesReplaced = 0
    public var nodesUpdated = 0
    public var connectionsAdded = 0
    public var connectionsRemoved = 0
    public var connectionsToggled = 0
    public var notesReplaced = 0

    public init() { }

    public var isEmpty: Bool { self == CloneReconcileReport() }
}

/// The id correspondence one reconcile works through: the source member's
/// local ids to template ids, and template ids to the target member's local
/// ids. The target side grows as the target gains what the source has; the
/// source side grows only where the source had an id its record did not,
/// which a template refresh beforehand makes rare.
struct CloneSyncContext
{
    private(set) var templateByLocal: [String: String]
    private(set) var localByTemplate: [String: String]
    private(set) var sourceRecordGrowth: [String: String] = [:]

    init(source: SubgraphNode, target: SubgraphNode)
    {
        self.templateByLocal = Dictionary(source.cloneRecord.map { ($0.value, $0.key) },
                                          uniquingKeysWith: { first, _ in first })
        self.localByTemplate = target.cloneRecord
    }

    /// The template id of one of the source's ids, assigned if unknown.
    mutating func templateID(forSourceLocal localID: String) -> String
    {
        if let known = templateByLocal[localID] { return known }
        let templateID = UUID().uuidString
        templateByLocal[localID] = templateID
        sourceRecordGrowth[templateID] = localID
        return templateID
    }

    func templateID(forSourceLocal id: UUID) -> String?
    {
        templateByLocal[id.uuidString]
    }

    /// The target's id for a template id, assigned and recorded if unknown.
    mutating func targetLocalID(forTemplate templateID: String) -> String
    {
        if let known = localByTemplate[templateID] { return known }
        let localID = UUID().uuidString
        localByTemplate[templateID] = localID
        return localID
    }

    func targetLocalID(forTemplate templateID: String) -> UUID?
    {
        localByTemplate[templateID].flatMap(UUID.init(uuidString:))
    }

    /// The target's id that stands for one of the source's ids, where both
    /// records already know it.
    func targetLocalID(forSourceLocal id: UUID) -> UUID?
    {
        guard let templateID = templateByLocal[id.uuidString] else { return nil }
        return targetLocalID(forTemplate: templateID)
    }

    mutating func record(targetLocal localID: UUID, forTemplate templateID: String)
    {
        localByTemplate[templateID] = localID.uuidString
    }

    /// Template ids the target currently records, by the target's local id.
    var templateByTargetLocal: [String: String]
    {
        Dictionary(localByTemplate.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
    }
}

extension Graph
{
    // MARK: - Sync

    /// Refreshes the set's template from `member`, then brings every sibling
    /// in line with it. Siblings nested inside the member, or containing it,
    /// are skipped: a set cannot contain itself.
    public func reconcileCloneSiblings(of member: SubgraphNode)
    {
        guard member.cloneSetID != nil else { return }
        self.refreshCloneTemplate(from: member)

        for sibling in self.cloneSiblings(of: member)
        {
            self.reconcileCloneMember(sibling, from: member)
        }
    }

    /// Syncs every set that `graph` sits inside, innermost first, taking the
    /// enclosing member as the source each time.
    public func reconcileCloneSets(enclosing graph: Graph)
    {
        var current: Graph? = graph
        while let owner = current?.ownerNode
        {
            if owner.cloneSetID != nil, let ownerGraph = owner.graph
            {
                ownerGraph.reconcileCloneSiblings(of: owner)
            }
            current = owner.graph
        }
    }

    /// Makes `target` match `source` node for node through the two members'
    /// records, touching only what differs so runtime state survives, and
    /// grows the records with anything new. A target with no record cannot be
    /// matched and is rebuilt from the template instead. Registers no undo
    /// steps: the edit that caused this is undone on the source, and the
    /// siblings follow again. Returns what changed; empty where nothing did
    /// or the pair cannot be synced.
    @discardableResult
    public func reconcileCloneMember(_ target: SubgraphNode, from source: SubgraphNode) -> CloneReconcileReport
    {
        var report = CloneReconcileReport()
        guard target !== source,
              let setID = source.cloneSetID, target.cloneSetID == setID,
              !target.subGraph.isDescendant(of: source.subGraph),
              !source.subGraph.isDescendant(of: target.subGraph)
        else { return report }

        let coordinator = self.cloneSetCoordinator
        let wasReconciling = coordinator.isReconciling
        coordinator.isReconciling = true
        defer { coordinator.isReconciling = wasReconciling }

        if target.cloneRecord.isEmpty
        {
            return self.recoverCloneMember(target)
        }

        var context = CloneSyncContext(source: source, target: target)
        target.subGraph.reconcile(from: source.subGraph, context: &context, report: &report)

        if context.localByTemplate != target.cloneRecord { target.cloneRecord = context.localByTemplate }
        if !context.sourceRecordGrowth.isEmpty
        {
            source.cloneRecord.merge(context.sourceRecordGrowth) { current, _ in current }
        }
        return report
    }

    /// Replaces `member` with a fresh instance of its set's template, in the
    /// same place with the same rename, re-binding the parent graph's wires
    /// to its published ports by their names. For a member whose record is
    /// missing, so nothing in it can be matched.
    @discardableResult
    internal func recoverCloneMember(_ member: SubgraphNode) -> CloneReconcileReport
    {
        var report = CloneReconcileReport()
        guard let setID = member.cloneSetID, let parent = member.graph else { return report }

        struct ParentWire { let otherPort: Port; let proxyName: String; let proxyKind: PortKind; let active: Bool }
        let memberPortIDs = Set(member.ports.map(\.id))
        let wires: [ParentWire] = parent.connections.compactMap { connection in
            guard let outlet = connection.outletPort, let inlet = connection.inletPort else { return nil }
            if memberPortIDs.contains(inlet.id)
            {
                return ParentWire(otherPort: outlet, proxyName: inlet.displayName, proxyKind: .Inlet, active: connection.active)
            }
            if memberPortIDs.contains(outlet.id)
            {
                return ParentWire(otherPort: inlet, proxyName: outlet.displayName, proxyKind: .Outlet, active: connection.active)
            }
            return nil
        }

        parent.withoutUndoRegistration {
            guard let fresh = parent.instantiateCloneSetMember(of: setID, at: member.offset) else { return }
            fresh.userName = member.userName
            report.nodesRemoved += member.subGraph.nodesRecursive().count
            report.nodesAdded += fresh.subGraph.nodesRecursive().count

            for wire in wires
            {
                guard let proxy = fresh.ports.first(where: { $0.kind == wire.proxyKind && $0.displayName == wire.proxyName })
                else { continue }
                let connection = wire.proxyKind == .Inlet
                    ? parent.connect(wire.otherPort, to: proxy)
                    : parent.connect(proxy, to: wire.otherPort)
                if let connection
                {
                    report.connectionsAdded += 1
                    if !wire.active { parent.setConnection(connection, active: false) }
                }
            }

            parent.delete(node: member)
        }
        return report
    }

    // MARK: - Template as source

    /// A new member of the set made from the template alone, added to this
    /// graph at `offset`: every id fresh and recorded, the set's member class.
    @discardableResult
    public func instantiateCloneSetMember(of setID: UUID, at offset: CGSize = .zero) -> SubgraphNode?
    {
        guard let set = self.cloneSet(for: setID) else { return nil }
        return self.instantiateMember(of: set, at: offset)
    }

    /// The same for a set this graph's document may not hold, as for the
    /// transient source an updated template is applied through.
    internal func instantiateMember(of set: CloneSet, at offset: CGSize = .zero) -> SubgraphNode?
    {
        let remap = Dictionary(uniqueKeysWithValues: Self.findAllUUIDs(in: set.templateObject).map { ($0, UUID().uuidString) })
        let subGraphObject = Self.remapUUIDs(in: set.templateObject, remap: remap, preservingKeys: [Self.cloneSetIDKey])

        let qualified = Self.qualifiedNodeID(fromSerializedType: set.memberNodeType)
        guard let registry = try? NodeRegistry.shared,
              let memberClass = registry.nodeClass(pluginID: qualified.pluginID, nodeID: qualified.nodeID) as? SubgraphNode.Type
        else { return nil }

        // Decode a member the way a document does: a blank node of the class
        // encoded for its own keys, with the template put in as its sub graph.
        let blank = memberClass.init(context: self.context)
        guard let blankData = try? JSONEncoder().encode(blank),
              var object = CloneSet.jsonObject(from: blankData)
        else { return nil }
        object["subGraph"] = subGraphObject
        object["proxyPorts"] = nil
        object[Self.cloneSetIDKey] = set.id.uuidString
        object["cloneRecord"] = remap

        let map = AnyCodableMap(type: set.memberNodeType, value: AnyCodable(object))
        guard let node = self.decodeNode(from: map) as? SubgraphNode else { return nil }
        node.offset = offset
        self.addNode(node)
        return node
    }

    /// Takes `templateJSON` as the set's template, as when a shared template
    /// changes outside the document, and reconciles every member from it.
    /// A transient member is made from the new template to serve as the
    /// source, then discarded.
    @discardableResult
    public func applyCloneTemplate(_ templateJSON: Data, to setID: UUID) -> [CloneReconcileReport]
    {
        guard let set = self.cloneSet(for: setID),
              let object = CloneSet.jsonObject(from: templateJSON)
        else { return [] }
        set.templateObject = object

        let scratch = Graph(context: self.context)
        guard let transient = scratch.instantiateMember(of: set) else { return [] }
        defer { scratch.delete(node: transient) }

        return self.cloneSetMembers(of: setID).map { member in
            self.reconcileCloneMember(member, from: transient)
        }
    }

    /// True when this graph is `ancestor` or sits anywhere inside it.
    internal func isDescendant(of ancestor: Graph) -> Bool
    {
        var current: Graph? = self
        while let graph = current
        {
            if graph === ancestor { return true }
            current = graph.ownerNode?.graph
        }
        return false
    }

    // MARK: - Reconcile one graph

    /// Makes this graph's design match `source` through `context`. Nested
    /// sub graphs reconcile first, so the proxies the parent's wires land on
    /// exist before the wires are diffed.
    internal func reconcile(from source: Graph, context: inout CloneSyncContext, report: inout CloneReconcileReport)
    {
        self.performWithBatchedConnectionTopologyChanges {
            self.withoutUndoRegistration {
                self.reconcileNodes(from: source, context: &context, report: &report)
                self.reconcileConnections(from: source, context: &context, report: &report)
                self.reconcileNotes(from: source, report: &report)
            }
        }

        if !report.isEmpty
        {
            self.rebuildPublishedParameterGroup()
            self.markConnectionsChanged()
        }
    }

    private func reconcileNodes(from source: Graph, context: inout CloneSyncContext, report: inout CloneReconcileReport)
    {
        let sourceTemplateIDs = Set(source.nodes.map { context.templateID(forSourceLocal: $0.id.uuidString) })
        let templateByTargetLocal = context.templateByTargetLocal
        for node in self.nodes
        {
            let templateID = templateByTargetLocal[node.id.uuidString]
            guard templateID == nil || !sourceTemplateIDs.contains(templateID!) else { continue }
            self.delete(node: node)
            report.nodesRemoved += 1
        }

        for sourceNode in source.nodes
        {
            let templateID = context.templateID(forSourceLocal: sourceNode.id.uuidString)
            if let localID = context.targetLocalID(forTemplate: templateID), let target = self.node(forID: localID)
            {
                if target.canReconcileInPlace(from: sourceNode)
                {
                    self.reconcileNodeState(target, from: sourceNode, context: &context, report: &report)
                    continue
                }

                self.delete(node: target)
                report.nodesReplaced += 1
            }
            else
            {
                report.nodesAdded += 1
            }

            if let copy = self.cloneNodeInstance(of: sourceNode, context: &context)
            {
                self.addNode(copy)
            }
        }
    }

    /// Layout, rename, published state and the values of inlets that are
    /// neither published nor wired, port by port through the records with
    /// the port's name as the fallback. Published inlet values are the
    /// member's own. A sub graph reconciles first.
    private func reconcileNodeState(_ target: Node, from source: Node,
                                    context: inout CloneSyncContext, report: inout CloneReconcileReport)
    {
        if let targetSubgraph = target as? SubgraphNode, let sourceSubgraph = source as? SubgraphNode
        {
            targetSubgraph.subGraph.reconcile(from: sourceSubgraph.subGraph, context: &context, report: &report)
        }

        var changed = false

        if target.offset != source.offset
        {
            target.offset = source.offset
            changed = true
        }

        if target.userName != source.userName
        {
            target.userName = source.userName
            changed = true
        }

        for sourcePort in source.ports
        {
            let templateID = context.templateID(forSourceLocal: sourcePort.id.uuidString)
            var port = context.targetLocalID(forTemplate: templateID).flatMap { localID in
                target.ports.first { $0.id == localID }
            }
            if port == nil,
               let byName = target.ports.first(where: {
                   $0.kind == sourcePort.kind && $0.name == sourcePort.name && $0.portType == sourcePort.portType
               })
            {
                port = byName
                context.record(targetLocal: byName.id, forTemplate: templateID)
            }
            guard let port else { continue }

            if port.published != sourcePort.published
            {
                port.published = sourcePort.published
                changed = true
            }

            if port.publishedName != sourcePort.publishedName
            {
                port.publishedName = sourcePort.publishedName
                changed = true
            }

            guard sourcePort.kind == .Inlet,
                  !sourcePort.published,
                  sourcePort.connections.isEmpty,
                  !(sourcePort is any ProxyPortProtocol),
                  sourcePort.portType == port.portType
            else { continue }

            let sourceValue = sourcePort.snapshotValue()
            if port.snapshotValue() != sourceValue
            {
                port.restoreValue(from: sourceValue)
                changed = true
            }
        }

        if changed { report.nodesUpdated += 1 }
    }

    private func reconcileConnections(from source: Graph, context: inout CloneSyncContext, report: inout CloneReconcileReport)
    {
        report.connectionsRemoved += self.pruneDanglingConnections()

        var desired: [UUID: [UUID: Bool]] = [:]
        for connection in source.connections
        {
            guard let outletID = context.targetLocalID(forSourceLocal: connection.outletPortID),
                  let inletID = context.targetLocalID(forSourceLocal: connection.inletPortID),
                  self.nodePort(forID: outletID) != nil, self.nodePort(forID: inletID) != nil
            else { continue }

            desired[outletID, default: [:]][inletID] = connection.active
        }

        var presentPairs: [UUID: Set<UUID>] = [:]
        for connection in self.connections
        {
            guard let active = desired[connection.outletPortID]?[connection.inletPortID]
            else
            {
                if self.disconnect(connection) { report.connectionsRemoved += 1 }
                continue
            }

            presentPairs[connection.outletPortID, default: []].insert(connection.inletPortID)
            if connection.active != active, self.setConnection(connection, active: active)
            {
                report.connectionsToggled += 1
            }
        }

        for (outletID, inlets) in desired
        {
            for (inletID, active) in inlets where presentPairs[outletID]?.contains(inletID) != true
            {
                guard let outlet = self.nodePort(forID: outletID),
                      let inlet = self.nodePort(forID: inletID),
                      let connection = self.connect(outlet, to: inlet)
                else { continue }

                report.connectionsAdded += 1
                if !active { self.setConnection(connection, active: false) }
            }
        }
    }

    private func reconcileNotes(from source: Graph, report: inout CloneReconcileReport)
    {
        let unchanged = self.notes.count == source.notes.count
            && zip(self.notes, source.notes).allSatisfy { $0.note == $1.note && $0.rect == $1.rect }
        guard !unchanged else { return }

        for note in self.notes { self.deleteNote(note) }
        for note in source.notes { self.addNote(Note(note: note.note, rect: note.rect)) }
        report.notesReplaced += 1
    }

    // MARK: - Node copies

    /// A fresh instance of `node` for this graph: every id mapped through the
    /// records to the target's id for it, existing or newly assigned, so a
    /// replaced node keeps the ids the parent's wires and the host know.
    private func cloneNodeInstance(of node: Node, context: inout CloneSyncContext) -> Node?
    {
        do
        {
            let qualifiedNodeID = try self.qualifiedNodeID(for: type(of: node))
            let map = AnyCodableMap(type: qualifiedNodeID.description, value: AnyCodable(node))
            let data = try JSONEncoder().encode(map)

            var remap: [String: String] = [:]
            for sourceLocal in Graph.findAllUUIDs(in: data)
            {
                let templateID = context.templateID(forSourceLocal: sourceLocal)
                remap[sourceLocal] = context.targetLocalID(forTemplate: templateID)
            }
            guard let rewritten = Graph.rewriteUUIDs(in: data, remap: remap, preservingKeys: [Self.cloneSetIDKey])
            else { return nil }

            let rewrittenMap = try JSONDecoder().decode(AnyCodableMap.self, from: rewritten)
            return self.decodeNode(from: rewrittenMap)
        }
        catch
        {
            print("cloneNodeInstance: failed for \(node): \(error)")
            return nil
        }
    }
}

// MARK: - Settings

extension Node
{
    /// Same class and same settings: the port set the code declares matches,
    /// so state can be applied port by port instead of replacing the node.
    fileprivate func canReconcileInPlace(from source: Node) -> Bool
    {
        type(of: self) == type(of: source)
            && self.cloneSettingsSignature() == source.cloneSettingsSignature()
    }

    /// Encoded keys that are not settings: identity, layout, port state, and
    /// for a subgraph the sub graph and clone links, all reconciled in place.
    private var cloneSettingsExcludedKeys: Set<String>
    {
        var keys: Set<String> = ["id", "nodeOffset", "ports", "userName"]
        if self is SubgraphNode
        {
            keys.formUnion(["subGraph", "proxyPorts", Graph.cloneSetIDKey, "cloneRecord"])
        }
        return keys
    }

    /// The node's settings as a comparable blob: its encoded form minus the
    /// excluded keys, with every UUID normalised. Two members whose nodes
    /// compare equal here can be reconciled in place; otherwise the sibling's
    /// node is replaced, since only decode rebuilds a settings-driven port set.
    internal func cloneSettingsSignature() -> Data?
    {
        guard let data = try? JSONEncoder().encode(self),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        for key in self.cloneSettingsExcludedKeys
        {
            object[key] = nil
        }

        let placeholder = "uuid"
        let remap = Dictionary(uniqueKeysWithValues: Graph.findAllUUIDs(in: object).map { ($0, placeholder) })
        let normalised = Graph.remapUUIDs(in: object, remap: remap)
        return try? JSONSerialization.data(withJSONObject: normalised, options: [.sortedKeys])
    }
}
