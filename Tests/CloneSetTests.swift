import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// Clone sets: Subgraph nodes that are instances of one stored graph, kept
/// identical in design while each executes on its own. A set is a root-level
/// object holding the stored graph as data; each member's sub graph is
/// decoded from it, so members hold the same nodes under the same ids. The
/// member edited last becomes the stored graph and its siblings are decoded
/// from it afresh. See CloneSet and SubgraphNode.cloneSetID.
@Suite("Clone Sets")
struct CloneSetTests
{
    private func makeContext() -> Context?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(device: device,
                       sampleCount: 1,
                       colorPixelFormat: .bgra8Unorm,
                       depthPixelFormat: .depth32Float,
                       stencilPixelFormat: .invalid)
    }

    private func roundTrip(_ graph: Graph, context: Context) throws -> Graph
    {
        try decode(JSONEncoder().encode(graph), context: context)
    }

    /// Encodes the way the editor saves a document: members in step with
    /// their set are written as a reference to it and per-member values only.
    private func saveCompactly(_ graph: Graph) throws -> Data
    {
        let encoder = JSONEncoder()
        encoder.userInfo[Graph.compactCloneMembersKey] = true
        return try encoder.encode(graph)
    }

    private func decode(_ data: Data, context: Context) throws -> Graph
    {
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        return try decoder.decode(Graph.self, from: data)
    }

    private func memberEntries(in data: Data) throws -> [[String: Any]]
    {
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let nodeMap = try #require(object["nodeMap"] as? [[String: Any]])
        return nodeMap.compactMap { $0["value"] as? [String: Any] }.filter { $0["cloneSetID"] != nil }
    }

    /// A member with two wired inner nodes, one published inlet and a nested
    /// subgraph, so instantiation and wiring are checked at every level.
    private struct MemberFixture
    {
        let graph: Graph
        let member: SubgraphNode
        let first: NumberBinaryOperator
        let second: NumberBinaryOperator
        let nested: SubgraphNode
        let nestedInner: NumberBinaryOperator
    }

    private func makeMemberFixture(context: Context) throws -> MemberFixture
    {
        let graph = Graph(context: context)
        let member = SubgraphNode(context: context)
        graph.addNode(member)

        let first = NumberBinaryOperator(context: context)
        let second = NumberBinaryOperator(context: context)
        let nested = SubgraphNode(context: context)
        let nestedInner = NumberBinaryOperator(context: context)
        member.subGraph.addNode(first)
        member.subGraph.addNode(second)
        member.subGraph.addNode(nested)
        nested.subGraph.addNode(nestedInner)

        _ = try #require(member.subGraph.connect(first.outputNumber, to: second.inputNumber1))
        first.inputNumber1.published = true
        first.inputNumber1.publishedName = "Amount"
        member.subGraph.rebuildPublishedParameterGroup()

        return MemberFixture(graph: graph, member: member, first: first, second: second,
                             nested: nested, nestedInner: nestedInner)
    }

    /// The node in `member` that stands for `node`: the same id, since every
    /// member is an instance of the same stored graph.
    private func counterpart<T: Node>(of node: T, in member: SubgraphNode) -> T?
    {
        member.subGraph.nodesRecursive().first { $0.id == node.id } as? T
    }

    // MARK: - Ownership

    @Test("A sub graph knows the node that owns it, after init and after decode")
    func subGraphKnowsOwner() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let outer = SubgraphNode(context: context)
        let inner = SubgraphNode(context: context)
        graph.addNode(outer)
        outer.subGraph.addNode(inner)

        #expect(graph.ownerNode == nil)
        #expect(outer.subGraph.ownerNode === outer)
        #expect(inner.subGraph.rootGraph === graph)

        let decoded = try roundTrip(graph, context: context)
        let decodedOuter = try #require(decoded.nodes.first as? SubgraphNode)
        let decodedInner = try #require(decodedOuter.subGraph.nodes.first as? SubgraphNode)
        #expect(decodedOuter.subGraph.ownerNode === decodedOuter)
        #expect(decodedInner.subGraph.rootGraph === decoded)
    }

    // MARK: - Sets and instances

    @Test("Duplicate as Clone starts a set on the root graph and instantiates the stored graph under the same ids")
    func duplicateAsCloneStartsASet() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        #expect(fixture.member.cloneSetID == nil)
        #expect(fixture.graph.cloneSets.isEmpty)

        let copy = try fixture.graph.duplicateAsClone(fixture.member)

        let set = try #require(fixture.graph.cloneSets.first)
        #expect(fixture.graph.cloneSets.count == 1)
        #expect(fixture.member.cloneSetID == set.id)
        #expect(copy.cloneSetID == set.id)
        #expect(set.name == "Set A")
        #expect(fixture.graph.cloneSet(for: set.id) === set)
        #expect(!set.graphJSON.isEmpty)

        // The copy is another node, with proxies of its own, over the same inner nodes and ports.
        #expect(copy.id != fixture.member.id)
        #expect(copy.subGraph !== fixture.member.subGraph)
        #expect(copy.subGraph.id != fixture.member.subGraph.id)
        #expect(Set(copy.subGraph.nodesRecursive().map(\.id)) == Set(fixture.member.subGraph.nodesRecursive().map(\.id)))
        #expect(copy.subGraph.nodesRecursive().allSatisfy { copied in
            !fixture.member.subGraph.nodesRecursive().contains { $0 === copied }
        })
        for node in fixture.member.subGraph.nodesRecursive()
        {
            let copied = try #require(counterpart(of: node, in: copy), "\(node)")
            #expect(Set(copied.ports.map(\.id)) == Set(node.ports.map(\.id)))
        }

        let copiedFirst = try #require(counterpart(of: fixture.first, in: copy))
        let copiedSecond = try #require(counterpart(of: fixture.second, in: copy))
        let copiedNested = try #require(counterpart(of: fixture.nested, in: copy))
        let copiedNestedInner = try #require(counterpart(of: fixture.nestedInner, in: copy))
        #expect(copiedFirst.inputNumber1.published)
        #expect(copiedFirst.inputNumber1.publishedName == "Amount")
        #expect(copy.subGraph.connections.count == 1)
        #expect(copy.subGraph.connections.first?.outletPort === copiedFirst.outputNumber)
        #expect(copy.subGraph.connections.first?.inletPort === copiedSecond.inputNumber1)
        #expect(copiedNestedInner.graph === copiedNested.subGraph)
        #expect(copiedNested.subGraph.id != fixture.nested.subGraph.id)

        // Each member's proxy wraps its own inner port under an id of its own.
        let sourceProxy = try #require(fixture.member.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == fixture.first.inputNumber1.id })
        let copyProxy = try #require(copy.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == copiedFirst.inputNumber1.id })
        #expect(sourceProxy.id != copyProxy.id)
        #expect(fixture.graph.nodePort(forID: copyProxy.id) === copyProxy)
        #expect(fixture.graph.nodePort(forID: sourceProxy.id) === sourceProxy)
    }

    @Test("Sets, instances and names survive a save")
    func setsRoundTrip() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let copy = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)
        try fixture.graph.renameCloneSet(setID, to: "Lyric Panel")

        let decoded = try roundTrip(fixture.graph, context: context)

        let decodedSet = try #require(decoded.cloneSet(for: setID))
        #expect(decodedSet.name == "Lyric Panel")
        let members = decoded.cloneSetMembers(of: setID)
        #expect(members.map(\.id) == [fixture.member.id, copy.id])
        #expect(Set(members[1].subGraph.nodesRecursive().map(\.id)) == Set(fixture.member.subGraph.nodesRecursive().map(\.id)))
        let original = try #require(fixture.graph.cloneSet(for: setID))
        #expect(NSDictionary(dictionary: decodedSet.graphObject) == NSDictionary(dictionary: original.graphObject))
    }

    @Test("Duplicate as Clone is one undoable step that also undoes set creation")
    func duplicateAsCloneUndoes() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let undoManager = UndoManager()
        fixture.graph.undoManager = undoManager

        let copy = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)

        undoManager.undo()
        #expect(fixture.graph.nodes.count == 1)
        #expect(fixture.member.cloneSetID == nil)
        #expect(fixture.graph.cloneSet(for: setID) == nil)

        undoManager.redo()
        #expect(fixture.graph.nodes.count == 2)
        #expect(fixture.member.cloneSetID == setID)
        #expect(fixture.graph.nodes.contains { $0 === copy })
        #expect(copy.cloneSetID == setID)
        #expect(fixture.graph.cloneSet(for: setID) != nil)
    }

    @Test("A plain duplicate of a member carries no clone links, and holds its own ids")
    func plainDuplicateLeavesTheSet() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        _ = try fixture.member.subGraph.duplicateAsClone(fixture.nested)
        _ = try fixture.graph.duplicateAsClone(fixture.member)

        let plain = try #require(fixture.graph.duplicateNodes([fixture.member]).first as? SubgraphNode)

        #expect(plain.cloneSetID == nil)
        #expect(plain.subGraph.subgraphNodesRecursive().allSatisfy { $0.cloneSetID == nil })
        #expect(Set(plain.subGraph.nodesRecursive().map(\.id)).isDisjoint(with: fixture.member.subGraph.nodesRecursive().map(\.id)))
    }

    @Test("Members are found across nesting levels, in document order")
    func membersAreDiscoveredAcrossNesting() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)

        let container = SubgraphNode(context: context)
        fixture.graph.addNode(container)
        let deepCopy = try fixture.graph.duplicateAsClone(fixture.member)
        fixture.graph.delete(node: deepCopy)
        container.subGraph.addNode(deepCopy)

        let members = fixture.graph.cloneSetMembers(of: setID)
        #expect(members.map(\.id) == [fixture.member.id, sibling.id, deepCopy.id])
        #expect(container.subGraph.cloneSetMembers(of: setID).map(\.id) == members.map(\.id))
        #expect(fixture.graph.cloneSiblings(of: sibling).map(\.id) == [fixture.member.id, deepCopy.id])
        #expect(fixture.graph.cloneSiblings(of: container).isEmpty)
    }

    @Test("Unlink leaves the set and gives nested sets their own copied graphs, undoably")
    func unlinkDetaches() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let undoManager = UndoManager()
        fixture.graph.undoManager = undoManager
        fixture.member.subGraph.undoManager = undoManager

        let nestedSibling = try fixture.member.subGraph.duplicateAsClone(fixture.nested)
        let nestedSetID = try #require(fixture.nested.cloneSetID)
        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)
        #expect(fixture.graph.cloneSets.count == 2)
        #expect(fixture.graph.cloneSetMembers(of: nestedSetID).count == 4)

        // Without a run loop every registration so far shares one undo group; the unlink gets its own.
        let unlinkUndo = UndoManager()
        fixture.graph.undoManager = unlinkUndo
        try fixture.graph.unlinkClone(sibling)

        #expect(sibling.cloneSetID == nil)
        #expect(fixture.graph.cloneSetMembers(of: setID).map(\.id) == [fixture.member.id])
        #expect(sibling.subGraph.nodes.count == 4)
        let detachedMembers = sibling.subGraph.subgraphNodesRecursive().filter { $0.cloneSetID != nil }
        #expect(detachedMembers.count == 2)
        let detachedSetID = try #require(detachedMembers.first?.cloneSetID)
        #expect(detachedSetID != nestedSetID)
        #expect(detachedMembers.allSatisfy { $0.cloneSetID == detachedSetID })
        #expect(fixture.graph.cloneSetMembers(of: nestedSetID).map(\.id) == [fixture.nested.id, nestedSibling.id])
        let detachedSet = try #require(fixture.graph.cloneSet(for: detachedSetID))
        let nestedSet = try #require(fixture.graph.cloneSet(for: nestedSetID))
        #expect(detachedSet.graphJSON == nestedSet.graphJSON)
        #expect(detachedSet.name == "Set C")

        unlinkUndo.undo()
        #expect(sibling.cloneSetID == setID)
        #expect(fixture.graph.cloneSetMembers(of: nestedSetID).count == 4)
        #expect(fixture.graph.cloneSet(for: detachedSetID) == nil)

        unlinkUndo.redo()
        #expect(sibling.cloneSetID == nil)
        #expect(fixture.graph.cloneSet(for: detachedSetID) != nil)
    }

    @Test("Sets are named in sequence, renamed undoably, and an empty name goes back to a system one")
    func namesAndRenames() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let undoManager = UndoManager()
        fixture.graph.undoManager = undoManager

        _ = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)
        let other = SubgraphNode(context: context)
        fixture.graph.addNode(other)
        _ = try fixture.graph.duplicateAsClone(other)
        let otherSetID = try #require(other.cloneSetID)
        #expect(fixture.graph.cloneSet(for: setID)?.name == "Set A")
        #expect(fixture.graph.cloneSet(for: otherSetID)?.name == "Set B")

        try fixture.graph.renameCloneSet(setID, to: "  Hero  ")
        #expect(fixture.graph.cloneSet(for: setID)?.name == "Hero")
        #expect(fixture.member.cloneSetInfo?.name == "Hero")
        #expect(fixture.member.deriveSubtitle() == "Hero")

        // Without a run loop every registration so far shares one undo group; the second rename gets its own.
        let renameUndo = UndoManager()
        fixture.graph.undoManager = renameUndo
        try fixture.graph.renameCloneSet(setID, to: "")
        #expect(fixture.graph.cloneSet(for: setID)?.name == "Set A")

        renameUndo.undo()
        #expect(fixture.graph.cloneSet(for: setID)?.name == "Hero")
        renameUndo.redo()
        #expect(fixture.graph.cloneSet(for: setID)?.name == "Set A")

        #expect(throws: FabricError.self) { try fixture.graph.renameCloneSet(UUID(), to: "X") }
    }

    @Test("A member reports itself linked, named by its set, and stops when unlinked")
    func memberStatus() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        #expect(fixture.member.deriveStatuses().isEmpty)
        #expect(fixture.member.deriveSubtitle() == nil)

        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        let status = try #require(fixture.member.deriveStatuses().first)
        #expect(status.message.contains("Set A"))
        #expect(status.message.contains("2 members"))
        if case .linked = status {} else { Issue.record("expected a linked status, got \(status)") }
        #expect(sibling.deriveSubtitle() == "Set A")

        try fixture.graph.unlinkClone(sibling)
        #expect(sibling.deriveStatuses().isEmpty)
        #expect(fixture.member.deriveStatuses().first?.message.contains("1 member.") == true)
    }

    @Test("The clone APIs throw typed errors rather than doing nothing")
    func apisThrow() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let elsewhere = Graph(context: context)

        #expect(throws: FabricError.self) { try elsewhere.duplicateAsClone(fixture.member) }
        #expect(throws: FabricError.self) { try fixture.graph.unlinkClone(fixture.member) }
        #expect(throws: FabricError.self) { try fixture.graph.renameCloneSet(UUID(), to: "X") }

        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        let stranger = SubgraphNode(context: context)
        fixture.graph.addNode(stranger)
        #expect(throws: FabricError.self) { try fixture.graph.reinstantiateCloneMember(stranger, from: fixture.member) }
        #expect(fixture.graph.nodes.contains { $0 === sibling })
    }
}

// MARK: - Sync

extension CloneSetTests
{
    /// A two-member set plus a fresh undo manager, so tests can both edit the
    /// source and assert that syncing never registers undo steps of its own.
    private struct PairFixture
    {
        let member: MemberFixture
        let sibling: SubgraphNode
        let undoManager: UndoManager

        var graph: Graph { member.graph }
        var source: Graph { member.member.subGraph }
        /// The sibling's current sub graph: another instance after every sync.
        var target: Graph { sibling.subGraph }

        func sync() { graph.reinstantiateCloneSiblings(of: member.member) }

        /// Syncs with a fresh undo manager on every graph, so any undo step
        /// left behind can only have come from the sync itself.
        func syncExpectingNoUndo(sourceLocation: SourceLocation = #_sourceLocation)
        {
            let fresh = UndoManager()
            graph.undoManager = fresh
            source.undoManager = fresh
            target.undoManager = fresh
            sync()
            #expect(fresh.canUndo == false, sourceLocation: sourceLocation)
        }

        /// The sibling's node for one of the source member's, at any depth:
        /// the same id in another instance.
        func counterpart<T: Node>(of node: T) -> T?
        {
            sibling.subGraph.nodesRecursive().first { $0.id == node.id } as? T
        }
    }

    private func makePair(context: Context) throws -> PairFixture
    {
        let member = try makeMemberFixture(context: context)
        let sibling = try member.graph.duplicateAsClone(member.member)
        let undoManager = UndoManager()
        member.graph.undoManager = undoManager
        member.member.subGraph.undoManager = undoManager
        sibling.subGraph.undoManager = undoManager
        return PairFixture(member: member, sibling: sibling, undoManager: undoManager)
    }

    @Test("Adding and wiring a node in one member appears in the sibling as a new instance of the whole sub graph")
    func addedNodeAppearsInSibling() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let before = pair.target
        let beforeFirst = try #require(pair.counterpart(of: pair.member.first))

        let added = NumberBinaryOperator(context: context)
        added.offset = CGSize(width: 300, height: 40)
        pair.source.addNode(added)
        _ = try #require(pair.source.connect(pair.member.second.outputNumber, to: added.inputNumber2))

        pair.syncExpectingNoUndo()

        #expect(pair.target !== before)
        #expect(pair.target.ownerNode === pair.sibling)
        #expect(before.ownerNode == nil)
        let addedCopy = try #require(pair.counterpart(of: added))
        let secondCopy = try #require(pair.counterpart(of: pair.member.second))
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        #expect(addedCopy !== added)
        #expect(firstCopy !== beforeFirst)
        #expect(addedCopy.offset == added.offset)
        #expect(pair.target.nodes.count == 4)
        #expect(pair.target.connections.count == 2)
        #expect(pair.target.connections.contains {
            $0.outletPort === secondCopy.outputNumber && $0.inletPort === addedCopy.inputNumber2
        })
    }

    @Test("Deleting a node in one member removes it and its wires from the sibling")
    func deletedNodeLeavesSibling() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.source.delete(node: pair.member.first)
        pair.syncExpectingNoUndo()

        #expect(pair.counterpart(of: pair.member.first) == nil)
        #expect(pair.target.nodes.count == 2)
        #expect(pair.target.connections.isEmpty)
        // The published inlet went with its node, and so did the proxies for it on both members.
        #expect(pair.sibling.ports.contains { $0 is any ProxyPortProtocol } == false)
        #expect(pair.member.member.ports.contains { $0 is any ProxyPortProtocol } == false)
    }

    @Test("Values of published inlets are each member's own; other values follow the source")
    func publishedValuesStayPerMember() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))

        pair.member.first.inputNumber1.value = 5     // published: per member
        firstCopy.inputNumber1.value = 7
        pair.member.first.inputNumber2.value = 9     // unpublished, unwired: design
        firstCopy.inputNumber2.value = 1

        pair.sync()

        let synced = try #require(pair.counterpart(of: pair.member.first))
        #expect(synced !== firstCopy)
        #expect(pair.member.first.inputNumber1.value == 5)
        #expect(synced.inputNumber1.value == 7)
        #expect(synced.inputNumber2.value == 9)
        // The proxy reads the per-member value too.
        let proxy = try #require(pair.sibling.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == synced.inputNumber1.id } as? NodePort<Float>)
        #expect(proxy.value == 7)
    }

    @Test("A re-instantiated member keeps its proxies, now over the new instance's ports, with the parent's wires onto them")
    func proxiesSurviveReinstantiation() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let upstream = NumberBinaryOperator(context: context)
        pair.graph.addNode(upstream)
        let proxy = try #require(pair.sibling.ports.first { $0 is any ProxyPortProtocol } as? NodePort<Float>)
        let proxyID = proxy.id
        _ = try #require(pair.graph.connect(upstream.outputNumber, to: proxy))
        proxy.published = true
        proxy.publishedName = "Gain"
        #expect(pair.graph.connections.count == 1)

        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.syncExpectingNoUndo()

        let kept = try #require(pair.sibling.ports.first { $0 is any ProxyPortProtocol })
        #expect(kept === proxy)
        #expect(kept.id == proxyID)
        #expect(kept.published)
        #expect(kept.publishedName == "Gain")
        #expect(pair.graph.connections.count == 1)
        #expect(pair.graph.connections.first?.inletPort === proxy)
        #expect(proxy.connections.count == 1)

        // The proxy now reads and feeds the new instance's port.
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        proxy.value = 3
        #expect(firstCopy.inputNumber1.value == 3)
        firstCopy.inputNumber1.value = 4
        #expect(proxy.value == 4)
    }

    @Test("A proxy published further up follows a nested member's re-instantiation")
    func publishedChainSurvivesNestedReinstantiation() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        // The nested member's published inlet, published on through the outer node.
        fixture.nestedInner.inputNumber1.published = true
        fixture.nested.subGraph.rebuildPublishedParameterGroup()
        let nestedProxy = try #require(fixture.nested.ports.first { $0 is any ProxyPortProtocol })
        nestedProxy.published = true
        fixture.member.subGraph.rebuildPublishedParameterGroup()
        let outerProxy = try #require(fixture.member.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == nestedProxy.id } as? NodePort<Float>)

        // A sibling of the nested member beside it, edited.
        let elsewhere = try fixture.member.subGraph.duplicateAsClone(fixture.nested)
        elsewhere.subGraph.addNode(NumberBinaryOperator(context: context))
        fixture.member.subGraph.reinstantiateCloneSiblings(of: elsewhere)

        #expect(fixture.nested.subGraph.nodes.count == 2)
        #expect(fixture.member.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == nestedProxy.id } === outerProxy)
        #expect(fixture.nested.ports.first { $0 is any ProxyPortProtocol } === nestedProxy)
        let newInner = try #require(fixture.nested.subGraph.node(forID: fixture.nestedInner.id) as? NumberBinaryOperator)
        #expect(newInner !== fixture.nestedInner)
        outerProxy.value = 6
        #expect(newInner.inputNumber1.value == 6)
    }

    @Test("A newly published port gets a proxy of its own id on every member")
    func newProxiesHaveTheirOwnIDs() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.member.second.inputNumber2.published = true
        pair.source.rebuildPublishedParameterGroup()
        pair.sync()

        let sourceProxy = try #require(pair.member.member.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == pair.member.second.inputNumber2.id })
        let siblingProxy = try #require(pair.sibling.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == pair.member.second.inputNumber2.id })
        #expect(sourceProxy.id != siblingProxy.id)
        #expect(sourceProxy.id != pair.member.second.inputNumber2.id)
        #expect(pair.graph.nodePort(forID: sourceProxy.id) === sourceProxy)
        #expect(pair.graph.nodePort(forID: siblingProxy.id) === siblingProxy)
    }

    @Test("A retired sub graph's nodes are stopped through the renderer, and the new instance's start at its next review")
    func retiredNodesAreStopped() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let renderer = GraphRenderer(context: context, graph: pair.graph)
        try renderer.startExecution()
        let oldNodes = pair.target.nodes
        let oldWired = oldNodes.filter { !$0.inputNodes.isEmpty || !$0.outputNodes.isEmpty }
        #expect(oldWired.count == 2)
        #expect(oldWired.allSatisfy { $0.executionState == .started })

        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.sync()

        #expect(oldNodes.allSatisfy { $0.executionState == .disabled })
        #expect(pair.target.nodes.allSatisfy { $0.executionState == .disabled })
        try renderer.synchronizeLifecycle()
        let newWired = pair.target.nodes.filter { !$0.inputNodes.isEmpty || !$0.outputNodes.isEmpty }
        #expect(newWired.count == 2)
        #expect(newWired.allSatisfy { $0.executionState == .started })
        try renderer.stopExecution()
    }

    @Test("A Deferred member's renderer follows its re-instantiated sub graph")
    func deferredRendererFollows() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let deferred = DeferredSubgraphNode(context: context)
        graph.addNode(deferred)
        deferred.subGraph.addNode(NumberBinaryOperator(context: context))
        let sibling = try #require(try graph.duplicateAsClone(deferred) as? DeferredSubgraphNode)
        #expect(sibling.childGraphRenderer?.graph === sibling.subGraph)

        deferred.subGraph.addNode(NumberBinaryOperator(context: context))
        graph.reinstantiateCloneSiblings(of: deferred)

        #expect(sibling.subGraph.nodes.count == 2)
        #expect(sibling.childGraphRenderer?.graph === sibling.subGraph)
    }

    @Test("Edits made in a sibling before it was re-instantiated can no longer be undone")
    @MainActor
    func siblingUndoIsForgotten() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator

        pair.target.addNode(NumberBinaryOperator(context: context))   // an edit in B, undoable
        #expect(pair.undoManager.canUndo)
        coordinator.flush()                                             // A follows B
        #expect(pair.source.nodes.count == 4)

        pair.source.addNode(NumberBinaryOperator(context: context))   // an edit in A
        coordinator.flush()                                             // B re-instantiated
        #expect(pair.target.nodes.count == 5)

        pair.undoManager.undo()                                         // A's edit
        coordinator.flush()
        #expect(pair.source.nodes.count == 4)
        #expect(pair.target.nodes.count == 4)
        #expect(pair.undoManager.canUndo == false)                      // B's edit is gone with B's old graph
    }

    @Test("Layout, renames and notes follow the source")
    func layoutAndRenameFollow() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.member.first.offset = CGSize(width: -120, height: 64)
        pair.member.first.userName = "Gain"
        let note = Note(note: "Feed this from the clock", rect: CGRect(x: 1, y: 2, width: 300, height: 100))
        pair.source.addNote(note)

        pair.sync()

        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        #expect(firstCopy.offset == pair.member.first.offset)
        #expect(firstCopy.userName == "Gain")
        #expect(pair.target.notes.count == 1)
        #expect(pair.target.notes.first?.note == note.note)
        #expect(pair.target.notes.first?.rect == note.rect)
    }

    @Test("A settings change reaches the sibling, ports rebuilt or not")
    func settingsChangesFollow() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let sampler = SampleAndHoldNode(context: context)
        sampler.strategy = PortType.Float.rawValue
        pair.source.addNode(sampler)
        let expression = MathExpressionNode(context: context, expression: "sin(x) + y")
        pair.source.addNode(expression)
        pair.sync()
        #expect(pair.counterpart(of: sampler)?.strategy == PortType.Float.rawValue)
        #expect(pair.counterpart(of: expression)?.stringExpression == "sin(x) + y")

        sampler.strategy = PortType.Virtual.rawValue
        expression.stringExpression = "cos(x) + y"
        pair.syncExpectingNoUndo()

        #expect(pair.counterpart(of: sampler)?.strategy == PortType.Virtual.rawValue)
        #expect(pair.counterpart(of: expression)?.stringExpression == "cos(x) + y")
    }

    @Test("Edits inside a nested subgraph reach the sibling's nested subgraph")
    func nestedEditsFollow() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let deepAdded = NumberBinaryOperator(context: context)
        pair.member.nested.subGraph.addNode(deepAdded)
        _ = try #require(pair.member.nested.subGraph.connect(pair.member.nestedInner.outputNumber, to: deepAdded.inputNumber1))

        pair.sync()

        let nestedCopy = try #require(pair.counterpart(of: pair.member.nested))
        let deepCopy = try #require(pair.counterpart(of: deepAdded))
        let innerCopy = try #require(pair.counterpart(of: pair.member.nestedInner))
        #expect(deepCopy.graph === nestedCopy.subGraph)
        #expect(nestedCopy.subGraph.connections.contains {
            $0.outletPort === innerCopy.outputNumber && $0.inletPort === deepCopy.inputNumber1
        })
    }

    @Test("A nested set inside a member syncs through the outer set, and the nested members keep their own values")
    @MainActor
    func nestedSetsSync() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator

        pair.member.nestedInner.inputNumber1.published = true
        pair.member.nested.subGraph.rebuildPublishedParameterGroup()
        let nestedSibling = try pair.source.duplicateAsClone(pair.member.nested)
        coordinator.flush()
        let nestedSetID = try #require(pair.member.nested.cloneSetID)
        #expect(pair.graph.cloneSetMembers(of: nestedSetID).count == 4)

        // Per-member values on the nested members, inside both outer members.
        let siblingNested = try #require(pair.counterpart(of: pair.member.nested))
        let siblingNestedInner = try #require(pair.counterpart(of: pair.member.nestedInner))
        pair.member.nestedInner.inputNumber1.value = 1
        siblingNestedInner.inputNumber1.value = 2
        let innerInNestedSibling = try #require(nestedSibling.subGraph.node(forID: pair.member.nestedInner.id) as? NumberBinaryOperator)
        innerInNestedSibling.inputNumber1.value = 3
        #expect(siblingNested.subGraph.nodes.count == 1)

        // An edit inside the nested member reaches every nested member, in both outer members.
        pair.member.nested.subGraph.addNode(NumberBinaryOperator(context: context))
        coordinator.flush()

        #expect(nestedSibling.subGraph.nodes.count == 2)
        let siblingNestedAfter = try #require(pair.counterpart(of: pair.member.nested))
        #expect(siblingNestedAfter.subGraph.nodes.count == 2)
        #expect(pair.graph.cloneSetMembers(of: nestedSetID).allSatisfy { $0.subGraph.nodes.count == 2 })
        #expect(pair.member.nestedInner.inputNumber1.value == 1)
        #expect((pair.counterpart(of: pair.member.nestedInner))?.inputNumber1.value == 2)
        #expect((nestedSibling.subGraph.node(forID: pair.member.nestedInner.id) as? NumberBinaryOperator)?.inputNumber1.value == 3)
    }

    @Test("A member moved inside a member of its own set is unlinked")
    func selfNestingUnlinks() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)

        pair.graph.delete(node: pair.sibling)
        pair.source.addNode(pair.sibling)

        #expect(pair.sibling.cloneSetID == nil)
        #expect(pair.graph.cloneSetMembers(of: setID).map(\.id) == [pair.member.member.id])
    }

    @Test("Sync stores the member once and leaves siblings alone when nothing changed")
    func unchangedSourceSyncsNothing() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let before = pair.target

        pair.sync()

        #expect(pair.target === before)
    }
}

// MARK: - Live sync

extension CloneSetTests
{
    @Test("Edits inside a member bump its graph's content revision, through the member's own subscriptions")
    @MainActor
    func editsBumpRevision() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        var revision = pair.source.contentRevision

        func expectBump(_ what: String, sourceLocation: SourceLocation = #_sourceLocation)
        {
            #expect(pair.source.contentRevision > revision, Comment(rawValue: what), sourceLocation: sourceLocation)
            revision = pair.source.contentRevision
        }

        pair.member.first.offset = CGSize(width: 10, height: 10)
        expectBump("move")
        pair.member.first.userName = "Renamed"
        expectBump("rename")
        pair.member.second.inputNumber2.published = true
        expectBump("publish")
        pair.member.second.inputNumber2.published = false
        expectBump("unpublish")
        pair.member.first.inputNumber2.value = 42
        expectBump("unwired, unpublished value")
        pair.member.nestedInner.offset = CGSize(width: 5, height: 5)
        #expect(pair.member.nested.subGraph.contentRevision > 0)
        expectBump("nested move reaches the enclosing member too")
    }

    @Test("Values arriving on published or wired inlets are not edits")
    @MainActor
    func drivenValuesDoNotBump() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let revision = pair.source.contentRevision

        pair.member.first.inputNumber1.value = 3       // published: per member
        pair.member.second.inputNumber1.value = 4      // wired: driven

        #expect(pair.source.contentRevision == revision)
    }

    @Test("An edit inside a member schedules a sync; flushing applies it and settles")
    @MainActor
    func editSchedulesSync() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator
        #expect(coordinator.hasPendingSync == false)

        pair.source.addNode(NumberBinaryOperator(context: context))
        #expect(coordinator.hasPendingSync)
        #expect(pair.target.nodes.count == 3)

        coordinator.flush()
        #expect(coordinator.hasPendingSync == false)
        #expect(pair.target.nodes.count == 4)
        #expect(pair.undoManager.canUndo)         // the edit itself
        pair.undoManager.undo()
        coordinator.flush()
        #expect(pair.target.nodes.count == 3)
    }

    @Test("The debounce fires on its own")
    @MainActor
    func debounceFires() async throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        pair.graph.cloneSetCoordinator.debounceInterval = .milliseconds(20)

        pair.source.addNode(NumberBinaryOperator(context: context))
        #expect(pair.target.nodes.count == 3)

        await pair.graph.cloneSetCoordinator.settle()

        #expect(pair.target.nodes.count == 4)
        #expect(pair.graph.cloneSetCoordinator.hasPendingSync == false)
    }

    @Test("When two members are edited before a sync, the later edit wins")
    @MainActor
    func laterEditorWins() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))

        pair.member.first.inputNumber2.value = 1      // edit in A
        firstCopy.inputNumber2.value = 2               // then in B
        coordinator.flush()

        // A was re-instantiated from B, so A's node is found again by id.
        let firstInA = try #require(pair.source.node(forID: pair.member.first.id) as? NumberBinaryOperator)
        #expect(firstInA !== pair.member.first)
        #expect(firstInA.inputNumber2.value == 2)
        #expect(pair.counterpart(of: pair.member.first)?.inputNumber2.value == 2)
    }

    @Test("Edits in a nested member of one sibling and in the other sibling before a sync both survive")
    @MainActor
    func nestedAndOuterEditsBothSurvive() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator
        _ = try pair.source.duplicateAsClone(pair.member.nested)
        coordinator.flush()
        let nestedSetID = try #require(pair.member.nested.cloneSetID)

        // An edit inside a nested member of B, then an edit in A.
        let nestedInB = try #require(pair.counterpart(of: pair.member.nested))
        nestedInB.subGraph.addNode(NumberBinaryOperator(context: context))
        pair.source.addNode(NumberBinaryOperator(context: context))
        coordinator.flush()

        #expect(pair.source.nodes.count == 5)
        #expect(pair.target.nodes.count == 5)
        #expect(pair.graph.cloneSetMembers(of: nestedSetID).count == 4)
        #expect(pair.graph.cloneSetMembers(of: nestedSetID).allSatisfy { $0.subGraph.nodes.count == 2 })
    }

    @Test("Undoing an edit on the source syncs the siblings back")
    @MainActor
    func undoSyncsBack() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator

        pair.source.addNode(NumberBinaryOperator(context: context))
        coordinator.flush()
        #expect(pair.target.nodes.count == 4)

        pair.undoManager.undo()
        coordinator.flush()

        #expect(pair.source.nodes.count == 3)
        #expect(pair.target.nodes.count == 3)
    }

    @Test("A node added after a sync is watched from the next sync on")
    @MainActor
    func addedNodesAreWatched() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator

        let added = NumberBinaryOperator(context: context)
        pair.source.addNode(added)
        coordinator.flush()

        added.inputNumber1.value = 8
        #expect(coordinator.hasPendingSync)
        coordinator.flush()
        #expect(pair.counterpart(of: added)?.inputNumber1.value == 8)

        // And the sibling's new instance is watched too; A is then re-instantiated from B.
        let addedCopy = try #require(pair.counterpart(of: added))
        addedCopy.inputNumber1.value = 9
        #expect(coordinator.hasPendingSync)
        coordinator.flush()
        #expect((pair.source.node(forID: added.id) as? NumberBinaryOperator)?.inputNumber1.value == 9)
    }

    @Test("Edits outside any clone set schedule nothing, and an unlinked member stops watching")
    @MainActor
    func editsOutsideSetsScheduleNothing() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator

        pair.graph.addNode(NumberBinaryOperator(context: context))
        #expect(coordinator.hasPendingSync == false)

        try pair.graph.unlinkClone(pair.sibling)
        let siblingSecond = try #require(pair.target.nodes.compactMap { $0 as? NumberBinaryOperator }.last)
        let revision = pair.target.contentRevision
        siblingSecond.inputNumber2.value = 11
        #expect(pair.target.contentRevision == revision)
        #expect(coordinator.hasPendingSync == false)
    }

    @Test("A save on a background queue still flushes the pending sync")
    func backgroundSaveFlushesPendingSync() async throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        await MainActor.run {
            pair.source.addNode(NumberBinaryOperator(context: context))
            #expect(pair.target.nodes.count == 3)
        }

        // FileDocument.fileWrapper(configuration:) runs off the main thread.
        await Task.detached { pair.graph.flushPendingCloneSync() }.value

        #expect(pair.target.nodes.count == 4)
    }

    @Test("The view model mirrors the linked status as membership changes")
    @MainActor
    func viewModelMirrorsLinkedStatus() async throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let viewModel = fixture.graph.viewModel(for: fixture.member)
        #expect(viewModel.status == nil)

        // Mirrors arrive on the main queue; poll briefly rather than sleep a fixed time.
        func settle(until condition: @escaping () -> Bool) async throws
        {
            for _ in 0..<50 where !condition()
            {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        try await settle { viewModel.status?.message.contains("2 members") == true }
        #expect(viewModel.status?.message.contains("2 members") == true)
        #expect(viewModel.subtitle == "Set A")

        fixture.member.userName = "Left"
        try await settle { viewModel.subtitle == "Left" }
        #expect(viewModel.subtitle == "Left")
        #expect(viewModel.status?.message.contains("Set A") == true)

        fixture.graph.delete(node: sibling)
        try await settle { viewModel.status?.message.contains("1 member.") == true }
        #expect(viewModel.status?.message.contains("1 member.") == true)
    }
}

// MARK: - Storage by reference

extension CloneSetTests
{
    @Test("A saved document holds the graph once and members as a reference and per-member values")
    @MainActor
    func membersSaveByReference() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)
        _ = try pair.member.member.subGraph.duplicateAsClone(pair.member.nested)   // a nested set inside the member
        pair.graph.cloneSetCoordinator.flush()

        // A parent wire onto the sibling's published inlet, and a per-member value on it.
        let upstream = NumberBinaryOperator(context: context)
        pair.graph.addNode(upstream)
        let proxy = try #require(pair.sibling.ports.first { $0.kind == .Inlet && $0.displayName == "Amount" })
        _ = try #require(pair.graph.connect(upstream.outputNumber, to: proxy))
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        pair.member.first.inputNumber1.value = 1
        firstCopy.inputNumber1.value = 5
        pair.graph.cloneSetCoordinator.flush()

        let data = try saveCompactly(pair.graph)
        let entries = try memberEntries(in: data)
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0["subGraph"] == nil })
        #expect(entries.allSatisfy { $0["memberValues"] != nil })

        let decoded = try decode(data, context: context)
        let members = decoded.cloneSetMembers(of: setID)
        #expect(members.map(\.id) == [pair.member.member.id, pair.sibling.id])
        let decodedSibling = members[1]
        #expect(Set(decodedSibling.subGraph.nodesRecursive().map(\.id)) == Set(pair.sibling.subGraph.nodesRecursive().map(\.id)))
        #expect(decodedSibling.subGraph.id != members[0].subGraph.id)
        let decodedFirstCopy = try #require(decodedSibling.subGraph.node(forID: firstCopy.id) as? NumberBinaryOperator)
        #expect(decodedFirstCopy.inputNumber1.value == 5)
        let decodedMemberFirst = try #require(members[0].subGraph.node(forID: pair.member.first.id) as? NumberBinaryOperator)
        #expect(decodedMemberFirst.inputNumber1.value == 1)
        // The parent's wire onto the sibling's proxy survived.
        let decodedProxy = try #require(decoded.nodePort(forID: proxy.id))
        #expect(decodedProxy.node === decodedSibling)
        #expect(decoded.connections.contains { $0.inletPortID == proxy.id })
        // The nested set inside came back as a set of its own.
        #expect(decoded.cloneSets.count == 2)
        let nestedSetID = try #require(pair.member.nested.cloneSetID)
        #expect(decoded.cloneSetMembers(of: nestedSetID).count == 4)
    }

    @Test("An edit still on the debounce reaches the siblings when its member leaves the set")
    @MainActor
    func unlinkCarriesThePendingEdit() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        // An edit left waiting on the debounce, as leaving by the menu would.
        pair.source.addNode(NumberBinaryOperator(context: context))
        #expect(pair.graph.cloneSetCoordinator.hasPendingSync)

        try pair.graph.unlinkClone(pair.member.member)
        pair.graph.cloneSetCoordinator.flush()

        #expect(pair.target.nodes.count == 4)
        #expect(pair.member.member.cloneSetID == nil)
    }

    @Test("A re-instantiated member watches the tree it has now")
    @MainActor
    func reinstantiatedMemberIsStillWatched() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        // A sync replaces the sibling's whole tree.
        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.sync()

        // An edit of the sibling's design, on the tree it holds now, reaching
        // the set only through the sibling's own watcher.
        let siblingSecond = try #require(pair.counterpart(of: pair.member.second))
        siblingSecond.inputNumber2.value = 7
        #expect(pair.graph.cloneSetCoordinator.hasPendingSync)

        pair.graph.cloneSetCoordinator.flush()

        // The sibling was the last edited, so it is the source: the other
        // member is the one re-instantiated, under the same ids.
        let syncedSecond = try #require(pair.source.nodesRecursive().first { $0.id == pair.member.second.id } as? NumberBinaryOperator)
        #expect(syncedSecond.inputNumber2.value == 7)
    }

    @Test("Unpublishing inside a member takes the parent's wire onto its proxy with it")
    @MainActor
    func unpublishingInsideMemberTakesTheParentWire() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let proxy = try #require(pair.sibling.ports.first { $0.kind == .Inlet && $0.displayName == "Amount" })
        let upstream = NumberBinaryOperator(context: context)
        pair.graph.addNode(upstream)
        let wire = try #require(pair.graph.connect(upstream.outputNumber, to: proxy))

        let inner = try #require(pair.target.nodesRecursive()
            .compactMap { $0 as? NumberBinaryOperator }
            .first { $0.inputNumber1.published })

        pair.target.setPublished(false, on: inner.inputNumber1)

        #expect(!pair.sibling.ports.contains { $0.id == proxy.id })
        #expect(!pair.graph.connections.contains { $0 === wire })
        #expect(upstream.outputNumber.connections.isEmpty)

        // A member's proxies carry ids of their own, so the one that comes
        // back could never have been bound to the wire that named the old.
        pair.target.setPublished(true, on: inner.inputNumber1)
        let rebuilt = try #require(pair.sibling.ports.first {
            ($0 as? any ProxyPortProtocol)?.innerPortID == inner.inputNumber1.id
        })
        #expect(rebuilt.id != proxy.id)
        #expect(rebuilt.connections.isEmpty)
    }

    @Test("A member exposing a nested sub graph's knob saves and loads, each member's value its own")
    @MainActor
    func nestedPublishedProxySurvivesCompactSave() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)

        // Publish an inlet inside the nested sub graph, then publish the
        // proxy that gives the nested node on through the member: the
        // ordinary way a knob is brought up to the top.
        pair.member.nestedInner.inputNumber1.published = true
        pair.member.nestedInner.inputNumber1.publishedName = "Nested Amount"
        pair.member.nested.subGraph.rebuildPublishedParameterGroup()
        let nestedProxy = try #require(pair.member.nested.ports.first { $0.kind == .Inlet && $0.displayName == "Nested Amount" })
        nestedProxy.published = true
        pair.source.rebuildPublishedParameterGroup()
        pair.sync()

        // The published inlet's value is each member's own.
        let siblingNestedInner = try #require(pair.counterpart(of: pair.member.nestedInner))
        pair.member.nestedInner.inputNumber1.value = 3
        siblingNestedInner.inputNumber1.value = 9

        let data = try saveCompactly(pair.graph)
        let decoded = try decode(data, context: context)

        #expect(decoded.cloneSetMembers(of: setID).count == 2)
        #expect(decoded.missingNodeDiagnostics.isEmpty)

        // Every instance of a stored graph names its nodes alike, so each
        // member is asked for the id within its own sub graph.
        let nestedID = pair.member.nestedInner.id
        let members = decoded.cloneSetMembers(of: setID)
        let source = try #require(members.first?.subGraph.nodesRecursive().first { $0.id == nestedID } as? NumberBinaryOperator)
        let sibling = try #require(members.last?.subGraph.nodesRecursive().first { $0.id == nestedID } as? NumberBinaryOperator)
        #expect(source.inputNumber1.value == 3)
        #expect(sibling.inputNumber1.value == 9)
    }

    @Test("A member whose design has drifted from its set is saved in full, so nothing is lost")
    @MainActor
    func driftedMembersSaveInFull() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator

        pair.target.addNode(NumberBinaryOperator(context: context))
        coordinator.discardPendingSync()

        let data = try saveCompactly(pair.graph)
        let entries = try memberEntries(in: data)
        #expect(entries.count == 2)
        #expect(entries.filter { $0["subGraph"] != nil }.count == 1)

        let decoded = try decode(data, context: context)
        let setID = try #require(pair.member.member.cloneSetID)
        let members = decoded.cloneSetMembers(of: setID)
        #expect(members[0].subGraph.nodes.count == 3)
        #expect(members[1].subGraph.nodes.count == 4)
    }

    @Test("A set with no members left is dropped on save")
    func emptySetsAreDropped() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        try fixture.graph.unlinkClone(sibling)
        try fixture.graph.unlinkClone(fixture.member)
        #expect(fixture.graph.cloneSets.count == 1)

        let decoded = try roundTrip(fixture.graph, context: context)
        #expect(decoded.cloneSets.isEmpty)
    }

    @Test("A set that would contain one of its own members drops that member with a diagnostic rather than decoding without end")
    func selfContainingSetIsRefused() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)
        let set = try #require(fixture.graph.cloneSet(for: setID))

        // Forge a stored graph whose nodes include a member of the set itself:
        // the sibling, encoded as a reference the way a document writes one.
        let encoder = JSONEncoder()
        encoder.userInfo[Graph.compactCloneMembersKey] = true
        let nodeType = try fixture.graph.qualifiedNodeID(for: SubgraphNode.self).description
        let value = try #require(CloneSet.jsonObject(from: try encoder.encode(sibling)))
        var object = set.graphObject
        var nodeMap = object["nodeMap"] as? [[String: Any]] ?? []
        nodeMap.append(["type": nodeType, "value": value])
        object["nodeMap"] = nodeMap
        set.graphJSON = CloneSet.canonicalJSON(object)

        try sibling.reinstantiateSubGraph()
        #expect(sibling.subGraph.nodes.count == 3)
        #expect(sibling.subGraph.missingNodeDiagnostics.count == 1)
        #expect(sibling.subGraph.missingNodeDiagnostics.first?.summary.contains("contains one of its own members") == true)
    }
}

// MARK: - Fidelity

extension CloneSetTests
{
    /// Node types that need a device, a permission, a download or a file to
    /// construct; the encode/decode contract they rely on is the same.
    private static let liveSourceNamePattern = #"Camera|Audio|Screen|Syphon|Model|Movie|Video|Hand|Face|Pose|Vision|MIDI|OSC|Capture|Microphone|Speech|Image Loader|Loader|Recorder|Writer|Export"#

    @Test("Every core node type clones, and a clone encodes back to the stored graph")
    func everyCoreNodeTypeClonesCleanly() throws
    {
        guard let context = makeContext() else { return }
        let registry = try NodeRegistry.shared
        let graph = Graph(context: context)
        let member = SubgraphNode(context: context)
        graph.addNode(member)

        var constructed: [String] = []
        var skipped: [String] = []
        for wrapper in registry.availableNodes
        where wrapper.pluginBundleID == FabricCoreNodesPlugin.pluginID
            && wrapper.nodeName.range(of: Self.liveSourceNamePattern, options: .regularExpression) == nil
        {
            guard let node = try? wrapper.initializeNode(context: context) else
            {
                skipped.append(wrapper.nodeName)
                continue
            }
            member.subGraph.addNode(node)
            constructed.append(wrapper.nodeName)
        }
        #expect(constructed.count > 50, "constructed \(constructed.count), skipped \(skipped)")

        let sibling = try graph.duplicateAsClone(member)
        #expect(sibling.subGraph.nodes.count == member.subGraph.nodes.count)

        var mismatched: [String] = []
        for node in member.subGraph.nodes
        {
            guard let copy = sibling.subGraph.node(forID: node.id) else
            {
                mismatched.append("\(type(of: node)) did not clone")
                continue
            }
            if type(of: copy) != type(of: node)
            {
                mismatched.append("\(type(of: node)) cloned as \(type(of: copy))")
            }
        }
        #expect(mismatched.isEmpty, "\(mismatched)")

        // The clone is in step: encoding it gives the stored graph back.
        let setID = try #require(member.cloneSetID)
        let set = try #require(graph.cloneSet(for: setID))
        #expect(try Graph.cloneSetJSON(of: sibling.subGraph) == set.graphJSON)
    }
}
