//
//  Graph+CloneSet.swift
//  Fabric
//
//  Created by Claude on 10/9/26.
//

import Foundation
internal import AnyCodable

/// A member's view of its set: the source of its linked status and its
/// subtitle. See SubgraphNode.cloneSetInfo.
public struct CloneSetInfo: Equatable
{
    public let setID: UUID
    public let name: String
    public let memberCount: Int

    public init(setID: UUID, name: String, memberCount: Int)
    {
        self.setID = setID
        self.name = name
        self.memberCount = memberCount
    }

    public var message: String
    {
        "Clone set \(name), \(memberCount) \(memberCount == 1 ? "member" : "members"). Edits here reach every member."
    }

    /// The member's status: linked, to the set and its members.
    public var status: NodeStatus { .linked(message) }
}

/// Clone sets: groups of SubgraphNodes that are instances of one stored
/// graph, kept identical in design while each executes on its own. Members
/// are peers to edit: the member you edit is encoded as the stored graph and
/// its siblings are patched to it, holding the same nodes under the same
/// ids. See CloneSet for the stored graph and Graph+ClonePatch for the sync.
extension Graph
{
    // MARK: - Creation

    /// Adds a sibling of `node` to this graph: a new instance of its set's
    /// stored graph, under a node id and proxy ids of its own. Starts a set,
    /// with the node's sub graph as its stored graph, if the node is not in
    /// one yet. One undo step, and nothing of it remains if the copy cannot
    /// be made.
    @discardableResult
    public func duplicateAsClone(_ node: SubgraphNode,
                                 offset: CGSize = CGSize(width: 20, height: 20)) throws -> SubgraphNode
    {
        guard node.graph === self else
        {
            throw recoverableGraphError(.nodeNotInGraph, message: "Node \(node.id) does not belong to this graph.")
        }

        let previousSetID = node.cloneSetID
        var startedSet: CloneSet?

        // Nothing is registered with undo until the copy exists, so a failure
        // leaves neither a half-made set nor an undo step behind.
        let copy: SubgraphNode
        do
        {
            copy = try self.withoutUndoRegistration {
                if node.cloneSetID == nil
                {
                    let set = CloneSet(name: self.nextFreeCloneSetName(), graphJSON: Data())
                    self.addCloneSet(set)
                    node.setCloneMembership(setID: set.id)
                    startedSet = set
                }

                try self.refreshCloneSetGraph(from: node)
                return try self.instantiateCloneSibling(of: node, offset: offset)
            }
        }
        catch
        {
            self.withoutUndoRegistration {
                node.setCloneMembership(setID: previousSetID)
                if let startedSet { self.removeCloneSet(startedSet) }
            }
            throw error
        }

        self.registerDuplicateAsCloneUndo(copy: copy, source: node, startedSet: startedSet, previousSetID: previousSetID)
        self.cloneSetMembershipChanged(around: copy)
        return copy
    }

    /// A new member beside `node`: the node encoded as a reference to its
    /// set, given a fresh id and fresh proxy ids, and decoded, which
    /// instantiates the set's stored graph for it.
    private func instantiateCloneSibling(of node: SubgraphNode, offset: CGSize) throws -> SubgraphNode
    {
        let nodeType = try self.qualifiedNodeID(for: type(of: node)).description
        let encoder = JSONEncoder()
        encoder.userInfo[Self.cloneSetReferencesKey] = true
        let data = try encoder.encode(AnyCodableMap(type: nodeType, value: AnyCodable(node)))

        // Every id in the node's own encoding is fresh: its own, its proxies'.
        // The ids under the preserved keys are the inner ports' and the set's,
        // which the copy shares; the keys of its values map are inner port
        // ids too, and a rewrite never touches keys.
        var remap: [String: String] = [:]
        for uuid in Self.findAllUUIDs(in: data) { remap[uuid] = UUID().uuidString }
        let preserved: Set<String> = [Self.cloneSetIDKey, Self.innerPortIDKey]

        guard let copy = self.decodeNode(from: data, remap: remap, preservingKeys: preserved) as? SubgraphNode else
        {
            throw recoverableGraphError(.cloneOperationFailed, message: "\(node) could not be instantiated from its set.")
        }
        copy.offset = node.offset + offset
        self.addNode(copy)
        return copy
    }

    /// The JSON key whose UUID value ties a node to its clone set, and the
    /// key under which a proxy names its inner port: both left as they are
    /// when a member is copied, since the copy shares them.
    internal static let cloneSetIDKey = "cloneSetID"
    internal static let innerPortIDKey = "innerPortID"

    /// One undo step for a whole Duplicate as Clone: the copy goes, the
    /// source's membership goes back, a set that was started goes. Redo
    /// puts all three back.
    private func registerDuplicateAsCloneUndo(copy: SubgraphNode, source: SubgraphNode, startedSet: CloneSet?,
                                              previousSetID: UUID?)
    {
        let copyID = copy.id
        let sourceID = source.id
        let currentSetID = source.cloneSetID

        self.registerUndo { graph in
            guard let copy = graph.node(forID: copyID) as? SubgraphNode,
                  let source = graph.node(forID: sourceID) as? SubgraphNode
            else { return }
            let copyOffset = copy.offset
            graph.withoutUndoRegistration {
                graph.delete(node: copy)
                source.setCloneMembership(setID: previousSetID)
                if let startedSet { graph.removeCloneSet(startedSet) }
            }
            graph.cloneSetMembershipChanged(around: source)

            // The copy is out of the graph now: redo puts this object back.
            graph.registerUndo { graph in
                guard let source = graph.node(forID: sourceID) as? SubgraphNode else { return }
                graph.withoutUndoRegistration {
                    if let startedSet { graph.addCloneSet(startedSet) }
                    source.setCloneMembership(setID: currentSetID)
                    copy.offset = copyOffset
                    graph.addNode(copy)
                }
                graph.registerDuplicateAsCloneUndo(copy: copy, source: source, startedSet: startedSet,
                                                   previousSetID: previousSetID)
                graph.cloneSetMembershipChanged(around: copy)
            }
            graph.undoManager?.setActionName("Duplicate as Clone")
        }
        undoManager?.setActionName("Duplicate as Clone")
    }

    // MARK: - Stored graph

    /// Rewrites the set's stored graph from `member`'s sub graph. Returns
    /// true where that changed it. Throws where the member is in no set.
    @discardableResult
    internal func refreshCloneSetGraph(from member: SubgraphNode) throws -> Bool
    {
        guard let setID = member.cloneSetID, let set = self.cloneSet(for: setID) else
        {
            throw recoverableGraphError(.notACloneMember, message: "\(member) is not in a clone set.")
        }

        let json = try Self.cloneSetJSON(of: member.subGraph)
        guard Self.designComparableJSON(json) != set.comparableGraphJSON else { return false }
        set.graphJSON = json
        return true
    }

    /// A sub graph's encoding with every inlet value that is not design
    /// removed, at any depth: the form in which members' designs compare.
    /// The stored form keeps the values, so a member made from it alone still
    /// decodes. See `nonDesignInlets` for which values those are.
    internal static func designComparableJSON(_ graphJSON: Data) -> Data
    {
        guard let object = CloneSet.jsonObject(from: graphJSON) else { return graphJSON }
        return CloneSet.canonicalJSON(nonDesignInlets(inGraph: object).graph)
    }

    /// Why an inlet's value is not part of a member's design.
    internal enum NonDesignValue
    {
        /// Each member's own: an inlet published at the member's edge, or one
        /// further in published onward, proxy by proxy, to that edge. A
        /// nested member's edge is its own, whatever the outer member
        /// publishes. A knob a plain nested sub graph publishes but the member
        /// does not is design, set on the proxy like any other value.
        case memberOwn
        /// Arriving over a wire that is on, inside the graph or onto the proxy
        /// that forwards it. A wire switched off leaves its inlet holding a
        /// value set by hand.
        case driven
    }

    /// The inlets of an encoded sub graph whose values are not design, by
    /// path, with the graph those values are removed from. The one place the
    /// rule is written: the design comparison takes the graph, and
    /// memberOwnInlets looks the member's own inlets up by their paths. A
    /// path is the port's id, prefixed by the ids of the subgraph nodes it
    /// sits inside: two instances of a nested set hold their inner ports
    /// under the same ids, and are told apart by the node each sits in.
    ///
    /// It reads these encoding keys, and CloneSetContractTests fails if they
    /// move: a graph's `nodeMap` and its `connections`' `inletPortID` and
    /// `active`; a node entry's `value`, with `id`, `ports`, `proxyPorts`,
    /// `subGraph`, `memberValues` and the set id; a port's `payload.base`,
    /// with `id`, `kind`, `published`, `value` and `parameter.base.value`; a
    /// proxy's `base`, with `innerPortID`.
    internal static func nonDesignInlets(inGraph graph: [String: Any], atMemberEdge: Bool = true,
                                         ownFromAbove: Set<String> = [], drivenFromAbove: Set<String> = [],
                                         prefix: String = "") -> (graph: [String: Any], inlets: [String: NonDesignValue])
    {
        var graph = graph
        var inlets: [String: NonDesignValue] = [:]
        let wiredInletIDs = Set((graph["connections"] as? [[String: Any]] ?? [])
            .filter { $0["active"] as? Bool != false }
            .compactMap { $0["inletPortID"] as? String })

        func classify(_ port: [String: Any]) -> NonDesignValue?
        {
            guard port["kind"] as? String == PortKind.Inlet.rawValue, let id = port["id"] as? String else { return nil }
            if port["published"] as? Bool == true, atMemberEdge || ownFromAbove.contains(id) { return .memberOwn }
            if wiredInletIDs.contains(id) || drivenFromAbove.contains(id) { return .driven }
            return nil
        }

        graph["nodeMap"] = (graph["nodeMap"] as? [[String: Any]])?.map { entry in
            guard var node = entry["value"] as? [String: Any] else { return entry }

            node["ports"] = (node["ports"] as? [[String: Any]])?.map { port in
                guard var payload = port["payload"] as? [String: Any],
                      var base = payload["base"] as? [String: Any],
                      let reason = classify(base),
                      let id = base["id"] as? String
                else { return port }
                inlets[prefix + id] = reason
                base["value"] = nil
                if var parameter = base["parameter"] as? [String: Any], var parameterBase = parameter["base"] as? [String: Any]
                {
                    parameterBase["value"] = nil
                    parameter["base"] = parameterBase
                    base["parameter"] = parameter
                }
                payload["base"] = base
                var port = port
                port["payload"] = payload
                return port
            }

            // A nested member written as a reference to its set: its values are its own.
            node["memberValues"] = nil

            if let subGraph = node["subGraph"] as? [String: Any]
            {
                var ownInnerIDs = Set<String>()
                var drivenInnerIDs = Set<String>()
                for proxy in node["proxyPorts"] as? [[String: Any]] ?? []
                {
                    guard let base = proxy["base"] as? [String: Any],
                          let innerID = base["innerPortID"] as? String,
                          let reason = classify(base)
                    else { continue }
                    switch reason
                    {
                    case .memberOwn: ownInnerIDs.insert(innerID)
                    case .driven:    drivenInnerIDs.insert(innerID)
                    }
                }
                let nested = nonDesignInlets(inGraph: subGraph,
                                             atMemberEdge: node[Self.cloneSetIDKey] != nil,
                                             ownFromAbove: ownInnerIDs,
                                             drivenFromAbove: drivenInnerIDs,
                                             prefix: prefix + (node["id"] as? String ?? "") + "/")
                node["subGraph"] = nested.graph
                inlets.merge(nested.inlets, uniquingKeysWith: { first, _ in first })
            }

            var entry = entry
            entry["value"] = node
            return entry
        }
        return (graph, inlets)
    }

    /// A sub graph encoded the way a set stores one: nested members as
    /// references to their sets, keys sorted, and the graphs themselves, the
    /// one at the top and any nested sub graph, under no id. Every instance
    /// of a stored graph has graph ids of its own (see
    /// instantiateCloneSetGraph), so the stored form carries none and every
    /// member in step encodes to the same bytes.
    internal static func cloneSetJSON(of graph: Graph) throws -> Data
    {
        let encoder = JSONEncoder()
        encoder.userInfo[Self.cloneSetReferencesKey] = true
        let data = try encoder.encode(graph)
        guard let object = CloneSet.jsonObject(from: data) else
        {
            throw FabricError(.graph(.cloneOperationFailed), severity: .recoverable,
                              message: "The sub graph could not be encoded for its clone set.")
        }
        let neutral = Self.withGraphIDs(in: object) { Self.storedGraphID } as? [String: Any] ?? object
        return CloneSet.canonicalJSON(neutral)
    }

    /// The id every graph carries in a stored graph.
    private static let storedGraphID = UUID(uuid: UUID_NULL).uuidString

    // MARK: - Instantiation

    /// A fresh instance of the set's stored graph: the same nodes, ports and
    /// wires under the same ids, decoded the way a document is. Only the
    /// graphs themselves, the one at the top and any nested sub graph, take
    /// new ids: the editor and the renderer cache by graph id, and two
    /// instances of one stored graph must not pass for each other there.
    /// A set that contains one of its own members is refused where the
    /// member is met: that node is dropped with a diagnostic, as any node the
    /// document cannot decode is.
    internal static func instantiateCloneSetGraph(of setID: UUID, decodeContext: DecoderContext) throws -> Graph
    {
        guard let set = decodeContext.cloneSets.first(where: { $0.id == setID }) else
        {
            throw FabricError(.graph(.cloneSetNotFound), severity: .recoverable,
                              message: "No clone set \(setID) in this document.")
        }
        guard !decodeContext.instantiatingCloneSetIDs.contains(setID) else
        {
            throw FabricError(.graph(.cloneOperationFailed), severity: .recoverable,
                              message: "Clone set \(set.name) contains one of its own members.")
        }
        decodeContext.instantiatingCloneSetIDs.insert(setID)
        defer { decodeContext.instantiatingCloneSetIDs.remove(setID) }

        return try Self.decodeCloneInstance(of: set.graphObject, decodeContext: decodeContext)
    }

    /// An encoded sub graph decoded as a new instance, every graph in it
    /// under a fresh id; see instantiateCloneSetGraph.
    internal static func decodeCloneInstance(of graphObject: [String: Any], decodeContext: DecoderContext) throws -> Graph
    {
        let object = Self.withGraphIDs(in: graphObject) { UUID().uuidString }
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.context = decodeContext
        return try decoder.decode(Graph.self, from: data)
    }

    /// The object with every graph's id, at any depth, replaced by what
    /// `replacement` gives. A graph is the object that carries a node map.
    internal static func withGraphIDs(in object: Any, replacement: () -> String) -> Any
    {
        switch object
        {
        case let array as [Any]:
            return array.map { withGraphIDs(in: $0, replacement: replacement) }

        case var dict as [String: Any]:
            if dict["nodeMap"] != nil, dict["id"] is String
            {
                dict["id"] = replacement()
            }
            for (key, value) in dict
            {
                dict[key] = withGraphIDs(in: value, replacement: replacement)
            }
            return dict

        default:
            return object
        }
    }

    /// The context a node is decoded in outside a document load: paste,
    /// duplicate, a clone set member instantiating its sub graph.
    internal func makeDecoderContext() -> DecoderContext
    {
        let context = DecoderContext(documentContext: self.context, fileReferenceBaseURL: self.fileReferenceBaseURL)
        context.cloneSets = self.rootGraph.cloneSets
        return context
    }

    // MARK: - Discovery

    /// Every member of the set anywhere in the document, in document order.
    public func cloneSetMembers(of setID: UUID) -> [SubgraphNode]
    {
        self.rootGraph.subgraphNodesRecursive().filter { $0.cloneSetID == setID }
    }

    /// The other members of `node`'s set; empty outside a set.
    public func cloneSiblings(of node: SubgraphNode) -> [SubgraphNode]
    {
        guard let setID = node.cloneSetID else { return [] }
        return self.cloneSetMembers(of: setID).filter { $0 !== node }
    }

    /// This graph's member-own inlets, by path; see `nonDesignInlets`, which
    /// reads them from the graph's encoding.
    internal func memberOwnInlets() -> [String: Port]
    {
        guard let data = try? JSONEncoder().encode(self), let object = CloneSet.jsonObject(from: data) else { return [:] }
        var ports: [String: Port] = [:]
        for (path, reason) in Self.nonDesignInlets(inGraph: object).inlets where reason == .memberOwn
        {
            if let port = self.inlet(atPath: path) { ports[path] = port }
        }
        return ports
    }

    /// The port a path from `nonDesignInlets` names.
    private func inlet(atPath path: String) -> Port?
    {
        var components = path.split(separator: "/").map(String.init)
        guard let portID = components.popLast().flatMap(UUID.init(uuidString:)) else { return nil }
        var graph: Graph? = self
        for nodeID in components
        {
            graph = UUID(uuidString: nodeID).flatMap { (graph?.node(forID: $0) as? SubgraphNode)?.subGraph }
        }
        return graph?.nodePort(forID: portID)
    }

    /// Subgraph nodes in this graph and, depth first, in their sub graphs.
    internal func subgraphNodesRecursive() -> [SubgraphNode]
    {
        self.nodesRecursive().compactMap { $0 as? SubgraphNode }
    }

    /// Stores each set's design again from one of its members, as after a
    /// change every member made alike: file references rewritten for a new
    /// document location.
    internal func storeCloneSetDesigns()
    {
        for set in self.rootGraph.cloneSets
        {
            guard let member = self.rootGraph.cloneSetMembers(of: set.id).first else { continue }
            _ = try? self.refreshCloneSetGraph(from: member)
        }
    }

    // MARK: - Names

    /// Renames the set. Whitespace is trimmed; an empty name goes back to a
    /// system name, the lowest not in use by another set. Undoable.
    public func renameCloneSet(_ setID: UUID, to name: String) throws
    {
        guard let set = self.cloneSet(for: setID) else
        {
            throw recoverableGraphError(.cloneSetNotFound, message: "No clone set \(setID) in this document.")
        }

        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty
        {
            trimmed = self.nextFreeCloneSetName(ignoring: setID)
        }
        let previous = set.name
        guard previous != trimmed else { return }

        set.name = trimmed
        self.cloneSetMembershipChanged(setID: setID)

        self.registerUndo { graph in
            try? graph.renameCloneSet(setID, to: previous)
        }
        undoManager?.setActionName("Rename Clone Set")
    }

    /// "Set A", "Set B", ... "Set Z", "Set AA", ...: the first not in use by
    /// any set in the document, `excluding` names claimed in the same edit
    /// and `ignoring` the set being renamed, whose own name is free to it.
    internal func nextFreeCloneSetName(excluding claimed: Set<String> = [], ignoring setID: UUID? = nil) -> String
    {
        let used = Set(self.rootGraph.cloneSets.filter { $0.id != setID }.map(\.name)).union(claimed)
        var index = 0
        while true
        {
            let candidate = "Set \(Self.cloneSetLetters(for: index))"
            if !used.contains(candidate) { return candidate }
            index += 1
        }
    }

    private static func cloneSetLetters(for index: Int) -> String
    {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var letters = ""
        var remaining = index
        repeat
        {
            letters.insert(alphabet[remaining % alphabet.count], at: letters.startIndex)
            remaining = remaining / alphabet.count - 1
        }
        while remaining >= 0
        return letters
    }

    // MARK: - Unlink

    /// Takes `node` out of its set: it keeps its contents and becomes an
    /// ordinary subgraph. Sets nested inside it get sets of their own, each
    /// on a copy of the nested stored graph, so they detach from their
    /// counterparts in the former siblings while staying linked among
    /// themselves. Undoable.
    public func unlinkClone(_ node: SubgraphNode) throws
    {
        guard node.graph === self else
        {
            throw recoverableGraphError(.nodeNotInGraph, message: "Node \(node.id) does not belong to this graph.")
        }
        guard let setID = node.cloneSetID else
        {
            throw recoverableGraphError(.notACloneMember, message: "\(node) is not in a clone set.")
        }

        // A nested set parts with this member only where its other members
        // are inside the siblings left: linked through the set left, they
        // part with it. One with members elsewhere, or none, keeps its links.
        let nestedMembers = node.subGraph.subgraphNodesRecursive().filter { $0.cloneSetID != nil }
        let siblingSetIDs = Set(self.cloneSiblings(of: node).flatMap { $0.subGraph.subgraphNodesRecursive() }.compactMap(\.cloneSetID))
        let nestedSetIDs = Set(nestedMembers.compactMap(\.cloneSetID)).intersection(siblingSetIDs)
        var claimedNames = Set<String>()
        var detachedSets: [UUID: CloneSet] = [:]
        for nestedSetID in nestedSetIDs.sorted(by: { $0.uuidString < $1.uuidString })
        {
            guard let nestedSet = self.cloneSet(for: nestedSetID) else { continue }
            let name = self.nextFreeCloneSetName(excluding: claimedNames)
            claimedNames.insert(name)
            detachedSets[nestedSetID] = CloneSet(name: name, graphJSON: nestedSet.graphJSON)
        }

        undoManager?.beginUndoGrouping()
        defer
        {
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Unlink from Clones")
        }

        for set in detachedSets.values { self.addCloneSetUndoably(set) }

        self.setCloneMembership(setID: nil, on: node)
        for nestedMember in nestedMembers
        {
            guard let nestedSetID = nestedMember.cloneSetID, let detached = detachedSets[nestedSetID] else { continue }
            self.setCloneMembership(setID: detached.id, on: nestedMember)
        }

        self.cloneSetMembershipChanged(setID: setID)
        for nestedSetID in nestedSetIDs { self.cloneSetMembershipChanged(setID: nestedSetID) }
    }

    // MARK: - Bookkeeping

    internal func addCloneSetUndoably(_ set: CloneSet)
    {
        self.addCloneSet(set)
        self.registerUndo { graph in
            graph.removeCloneSetUndoably(set)
        }
    }

    internal func removeCloneSetUndoably(_ set: CloneSet)
    {
        self.removeCloneSet(set)
        self.registerUndo { graph in
            graph.addCloneSetUndoably(set)
        }
    }

    /// Undoable assignment of a node's set. The badge on every member of the
    /// sets touched is refreshed by `cloneSetMembershipChanged`.
    internal func setCloneMembership(setID: UUID?, on node: SubgraphNode)
    {
        let previousID = node.cloneSetID
        guard previousID != setID else { return }

        node.setCloneMembership(setID: setID)

        // The step is the node's graph's: a nested member is found there.
        (node.graph ?? self).registerUndo(on: node) { node in
            guard let graph = node.graph else { return }
            graph.setCloneMembership(setID: previousID, on: node)
            graph.cloneSetMembershipChanged(setID: previousID)
            graph.cloneSetMembershipChanged(setID: setID)
        }
    }

    /// The member count a set's badge shows changed; refresh every member.
    internal func cloneSetMembershipChanged(setID: UUID?)
    {
        guard let setID else { return }
        let members = self.cloneSetMembers(of: setID)
        for member in members
        {
            member.cloneMemberCount = members.count
            member.subtitleSubject.send()
        }
    }

    /// A node arrived or left, taking every member nested in it along:
    /// refresh every set any of them belongs to.
    internal func cloneSetMembershipChanged(around node: Node)
    {
        for setID in Set(Self.cloneMembers(in: node).compactMap(\.cloneSetID))
        {
            self.cloneSetMembershipChanged(setID: setID)
        }
    }

    /// `node` arrived in this graph or left it: a member arriving inside its
    /// own set is unlinked, then the sets of every member it took along are
    /// refreshed.
    internal func updateCloneSets(around node: Node)
    {
        if node.graph === self { self.unlinkMembersNestedInTheirOwnSet(in: node) }
        self.cloneSetMembershipChanged(around: node)
    }

    /// A set cannot contain itself. A member arriving in this graph is
    /// unlinked where a member of the same set encloses it, whether around
    /// this graph or in what arrived with it, and so is every member nested in
    /// what arrived that the same holds for. A document opening is caught here
    /// too: each graph is decoded before the member around it, so the members
    /// around a graph are checked as that member arrives.
    private func unlinkMembersNestedInTheirOwnSet(in node: Node)
    {
        self.unlinkMembers(in: node, enclosedBy: Set(self.enclosingCloneMembers.compactMap(\.cloneSetID)))
    }

    private func unlinkMembers(in node: Node, enclosedBy enclosingSetIDs: Set<UUID>)
    {
        guard let member = node as? SubgraphNode else { return }
        var enclosingSetIDs = enclosingSetIDs
        if let setID = member.cloneSetID
        {
            if enclosingSetIDs.contains(setID)
            {
                print("Graph: unlinking \(member) — a clone set cannot contain one of its own members")
            member.setCloneMembership(setID: nil)
                self.cloneSetMembershipChanged(setID: setID)
            }
            else
            {
                enclosingSetIDs.insert(setID)
            }
        }
        for inner in member.subGraph.nodes { self.unlinkMembers(in: inner, enclosedBy: enclosingSetIDs) }
    }

    /// `node`, where it is a member, and every member nested in it.
    internal static func cloneMembers(in node: Node) -> [SubgraphNode]
    {
        ([node] + ((node as? SubgraphNode)?.subGraph.nodesRecursive() ?? []))
            .compactMap { $0 as? SubgraphNode }
            .filter { $0.cloneSetID != nil }
    }

    /// Strips clone links from a node and everything nested in it, for copies
    /// that must not be members.
    internal static func clearCloneLinks(in node: Node)
    {
        guard let subgraphNode = node as? SubgraphNode else { return }
        subgraphNode.setCloneMembership(setID: nil)
        for inner in subgraphNode.subGraph.nodes { clearCloneLinks(in: inner) }
    }
}
