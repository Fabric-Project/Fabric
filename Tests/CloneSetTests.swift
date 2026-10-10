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
///
/// These test the model's own machinery; what any model must do for the
/// user is in CloneSetContractTests.
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

    @Test("A proxy a nested member makes has the same id in every instance of it, so the members around it stay in step")
    @MainActor
    func nestedMemberProxyIDsAgree() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        _ = try pair.source.duplicateAsClone(pair.member.nested)
        pair.graph.syncCloneSets()

        pair.member.nested.subGraph.setPublished(true, on: pair.member.nestedInner.inputNumber2)
        pair.graph.syncCloneSets()

        let sourceProxy = try #require(pair.member.nested.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == pair.member.nestedInner.inputNumber2.id })
        let siblingNested = try #require(pair.counterpart(of: pair.member.nested))
        let siblingProxy = try #require(siblingNested.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == pair.member.nestedInner.inputNumber2.id })
        #expect(siblingProxy !== sourceProxy)
        #expect(siblingProxy.id == sourceProxy.id)
        #expect(pair.member.member.isInStepWithCloneSet)
        #expect(pair.sibling.isInStepWithCloneSet)
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
}

// MARK: - Storage by reference

extension CloneSetTests
{
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

    @Test("A set that would contain one of its own members keeps that member as saved, reporting why, rather than decoding without end")
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
        let standIn = try #require(sibling.subGraph.nodes.compactMap { $0 as? SubgraphNode }.first { $0.id == sibling.id })
        #expect(standIn.cloneSetID == nil)
        #expect(standIn.status?.message.contains("contains one of its own members") == true)
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

    @Test("A canvas standing inside a sibling is told when a sync replaces what it shows, and edits there are recorded")
    @MainActor
    func canvasInsideSiblingIsToldOfTheSync() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let canvas = GraphCanvasContext(rootGraph: pair.graph)
        canvas.enter(pair.sibling)
        canvas.enter(try #require(pair.counterpart(of: pair.member.nested)))

        var told = false
        withObservationTracking { _ = canvas.currentGraph } onChange: { told = true }
        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.graph.syncCloneSets()

        #expect(told)
        #expect(canvas.currentGraph.undoManager === pair.undoManager)
    }
}
