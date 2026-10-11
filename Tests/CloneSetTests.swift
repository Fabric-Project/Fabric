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
        /// The sibling's sub graph: the same graph through every sync.
        var target: Graph { sibling.subGraph }

        func sync() { graph.patchCloneSiblings(of: member.member) }

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

    @Test("Adding and wiring a node in one member adds the node and the wire to the sibling, its other nodes left in place")
    func addedNodeAppearsInSibling() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let before = pair.target
        let beforeFirst = try #require(pair.counterpart(of: pair.member.first))
        let beforeSecond = try #require(pair.counterpart(of: pair.member.second))

        let added = NumberBinaryOperator(context: context)
        added.offset = CGSize(width: 300, height: 40)
        pair.source.addNode(added)
        _ = try #require(pair.source.connect(pair.member.second.outputNumber, to: added.inputNumber2))

        pair.syncExpectingNoUndo()

        #expect(pair.target === before)
        let addedCopy = try #require(pair.counterpart(of: added))
        #expect(addedCopy !== added)
        #expect(pair.counterpart(of: pair.member.first) === beforeFirst)
        #expect(pair.counterpart(of: pair.member.second) === beforeSecond)
        #expect(addedCopy.offset == added.offset)
        #expect(pair.target.nodes.count == 4)
        #expect(pair.target.nodes.map(\.id) == pair.source.nodes.map(\.id), "the sibling's nodes stand in the stored graph's order")
        #expect(pair.target.connections.count == 2)
        #expect(pair.target.connections.contains {
            $0.outletPort === beforeSecond.outputNumber && $0.inletPort === addedCopy.inputNumber2
        })
    }

    @Test("A sync that leaves a node alone leaves it clean, its own values untouched")
    func untouchedNodeStaysClean() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        firstCopy.inputNumber1.value = 7
        for node in pair.target.nodes { node.markClean() }

        pair.member.second.offset = CGSize(width: 80, height: 80)
        pair.sync()

        #expect(pair.counterpart(of: pair.member.second)?.offset == CGSize(width: 80, height: 80))
        #expect(!firstCopy.isDirty, "a node the sync left alone was not written to")
        #expect(firstCopy.inputNumber1.value == 7)
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

    @Test("A node a sync puts another in place of is stopped, its replacement starts at the next review, and nodes left alone keep running")
    func replacedNodeIsStoppedAndItsReplacementStarts() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let expression = MathExpressionNode(context: context, expression: "x + y")
        pair.source.addNode(expression)
        let x = try #require(expression.inputPorts().first { $0.name == "x" })
        _ = try #require(pair.source.connect(pair.member.second.outputNumber, to: x))
        pair.sync()

        let renderer = GraphRenderer(context: context, graph: pair.graph)
        try renderer.startExecution()
        let secondCopy = try #require(pair.counterpart(of: pair.member.second))
        let oldExpression = try #require(pair.counterpart(of: expression))
        #expect(secondCopy.executionState == .started)
        #expect(oldExpression.executionState == .started)

        expression.stringExpression = "x * y"
        pair.sync()

        let newExpression = try #require(pair.counterpart(of: expression))
        #expect(newExpression !== oldExpression)
        #expect(secondCopy.executionState == .started, "a node the sync left alone keeps running")
        try renderer.synchronizeLifecycle()
        #expect(oldExpression.executionState == .disabled, "the node put aside is reviewed like any node taken out")
        #expect(newExpression.executionState == .started)
        #expect(secondCopy.executionState == .started)
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

        // The proxy that comes back keeps its id, but not the wire, which
        // unpublishing took.
        pair.target.setPublished(true, on: inner.inputNumber1)
        let rebuilt = try #require(pair.sibling.ports.first {
            ($0 as? any ProxyPortProtocol)?.innerPortID == inner.inputNumber1.id
        })
        #expect(rebuilt.id == proxy.id)
        #expect(rebuilt.connections.isEmpty)
        #expect(upstream.outputNumber.connections.isEmpty)
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
        // the sibling, encoded as a reference the way a stored graph writes one.
        let encoder = JSONEncoder()
        encoder.userInfo[Graph.cloneSetReferencesKey] = true
        let nodeType = try fixture.graph.qualifiedNodeID(for: SubgraphNode.self).description
        let value = try #require(CloneSet.jsonObject(from: try encoder.encode(sibling)))
        var object = set.graphObject
        var nodeMap = object["nodeMap"] as? [[String: Any]] ?? []
        nodeMap.append(["type": nodeType, "value": value])
        object["nodeMap"] = nodeMap
        set.graphJSON = CloneSet.canonicalJSON(object)

        let instance = try Graph.instantiateCloneSetGraph(of: setID, decodeContext: fixture.graph.makeDecoderContext())
        #expect(instance.nodes.count == 3)
        #expect(instance.missingNodeDiagnostics.count == 1)
        #expect(instance.missingNodeDiagnostics.first?.summary.contains("contains one of its own members") == true)
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

    @Test("A canvas standing inside a sibling is told when a sync changes what it shows, and edits there are recorded")
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

    // MARK: - Undo across syncs

    /// Makes `body` one undo group of its own, as the editor's event loop
    /// does, the group's close syncing the sets around the edit.
    private func edit(_ undoManager: UndoManager, _ body: () throws -> Void) rethrows
    {
        undoManager.groupsByEvent = false
        while undoManager.groupingLevel > 0 { undoManager.endUndoGrouping() }
        undoManager.beginUndoGrouping()
        defer { undoManager.endUndoGrouping() }
        try body()
    }

    /// Every member in the document names a set the document holds.
    private func everyMemberHasItsSet(_ graph: Graph) -> Bool
    {
        graph.subgraphNodesRecursive().allSatisfy { member in
            member.cloneSetID.map { graph.cloneSet(for: $0) != nil } ?? true
        }
    }

    @Test("A value set in the inspector on a nested member's published inlet undoes after a sync has patched the member around it")
    @MainActor
    func nestedMemberValueUndoSurvivesReinstantiation() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        edit(pair.undoManager) { _ = try? pair.source.duplicateAsClone(pair.member.nested) }
        let nested = try #require(pair.member.member.subGraph.node(forID: pair.member.nested.id) as? SubgraphNode)
        let inner = try #require(nested.subGraph.node(forID: pair.member.nestedInner.id) as? NumberBinaryOperator)
        edit(pair.undoManager) { nested.subGraph.setPublished(true, on: inner.inputNumber2) }

        // The inspector of the outer member's graph shows the nested member's knob.
        let liveNested = try #require(pair.member.member.subGraph.node(forID: pair.member.nested.id) as? SubgraphNode)
        let proxy = try #require(liveNested.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == inner.inputNumber2.id })
        let parameter = try #require(proxy.parameter as? GenericParameter<Float>)
        let before = parameter.value
        edit(pair.undoManager) {
            parameter.value = 0.25
            pair.member.member.subGraph.registerValueChange(of: parameter, from: before, label: "Number B")
        }
        edit(pair.undoManager) { pair.target.addNode(NumberBinaryOperator(context: context)) }   // syncs into A

        pair.undoManager.undo()
        pair.undoManager.undo()
        let liveInner = try #require(pair.member.member.subGraph.nodesRecursive().first { $0.id == inner.id } as? NumberBinaryOperator)
        #expect(liveInner.inputNumber2.value == before)
    }

    @Test("Undoing Duplicate as Clone nested inside a member, after a sync has patched it, unlinks the live source and leaves no member without its set")
    @MainActor
    func nestedDuplicateUndoSurvivesReinstantiation() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let nestedID = pair.member.nested.id
        edit(pair.undoManager) { _ = try? pair.source.duplicateAsClone(pair.member.nested) }
        edit(pair.undoManager) { pair.target.addNode(NumberBinaryOperator(context: context)) }   // syncs into A

        pair.undoManager.undo()                                                                   // B's edit
        pair.undoManager.undo()                                                                   // the duplicate
        let liveNested = try #require(pair.member.member.subGraph.node(forID: nestedID) as? SubgraphNode)
        #expect(liveNested.cloneSetID == nil)
        #expect(pair.member.member.subGraph.nodes.count == 3)
        #expect(everyMemberHasItsSet(pair.graph))

        pair.undoManager.redo()
        #expect(pair.member.member.subGraph.nodes.count == 4)
        #expect(everyMemberHasItsSet(pair.graph))
    }

    @Test("A member's own published value set from the parent's inspector undoes after a sync has patched the member")
    @MainActor
    func ownValueFromParentUndoSurvivesReinstantiation() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let firstID = pair.member.first.id
        let proxy = try #require(pair.member.member.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == pair.member.first.inputNumber1.id })
        let parameter = try #require(proxy.parameter as? GenericParameter<Float>)
        let before = parameter.value

        edit(pair.undoManager) {
            parameter.value = 5
            pair.graph.registerValueChange(of: parameter, from: before, label: "Amount")
        }
        edit(pair.undoManager) { pair.target.addNode(NumberBinaryOperator(context: context)) }   // syncs into A
        let patched = try #require(pair.member.member.subGraph.node(forID: firstID) as? NumberBinaryOperator)
        #expect(patched.inputNumber1.value == 5, "the member keeps its own value through the sync")

        pair.undoManager.undo()
        pair.undoManager.undo()
        let live = try #require(pair.member.member.subGraph.node(forID: firstID) as? NumberBinaryOperator)
        #expect(live.inputNumber1.value == before)
    }

    @Test("A step made in a sub graph before it joined a set acts on the live node after a sync has patched its member")
    @MainActor
    func stepFromBeforeMembershipActsOnTheLiveInstance() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let plain = SubgraphNode(context: context)
        graph.addNode(plain)
        let undoManager = UndoManager()
        graph.undoManager = undoManager
        plain.subGraph.undoManager = undoManager

        let added = NumberBinaryOperator(context: context)
        edit(undoManager) { plain.subGraph.addNode(added) }
        var copy: SubgraphNode?
        edit(undoManager) { copy = try? graph.duplicateAsClone(plain) }
        let sibling = try #require(copy)
        edit(undoManager) { sibling.subGraph.addNode(NumberBinaryOperator(context: context)) }   // syncs into the source

        undoManager.undo()
        undoManager.undo()
        undoManager.undo()
        let live = try #require(graph.node(forID: plain.id) as? SubgraphNode)
        #expect(!live.subGraph.nodes.contains { $0.id == added.id })
        #expect(live.subGraph.nodes.isEmpty)
    }

    @Test("Undoing an edit puts the stored graph back, so making the same edit again syncs the siblings")
    @MainActor
    func undoPutsTheStoredGraphBack() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let set = try #require(pair.member.member.cloneSetID.flatMap(pair.graph.cloneSet(for:)))
        let storedBefore = set.graphJSON
        let parameter = try #require(pair.member.second.inputNumber2.parameter as? GenericParameter<Float>)
        let before = parameter.value

        func setDesignValue()
        {
            edit(pair.undoManager) {
                parameter.value = 3
                pair.source.registerValueChange(of: parameter, from: before, label: "Number B")
            }
        }

        setDesignValue()
        #expect(pair.counterpart(of: pair.member.second)?.inputNumber2.value == 3)
        pair.undoManager.undo()
        #expect(set.graphJSON == storedBefore)
        #expect(pair.counterpart(of: pair.member.second)?.inputNumber2.value == before)

        setDesignValue()
        #expect(pair.counterpart(of: pair.member.second)?.inputNumber2.value == 3)
    }

    @Test("Undoing an unpublish puts back a sibling's proxy published up a level, the wire onto the proxy over it, and its own value")
    @MainActor
    func undoPutsBackASiblingsProxyChain() throws
    {
        guard let context = makeContext() else { return }
        let root = Graph(context: context)
        let outer = SubgraphNode(context: context)
        root.addNode(outer)
        let graph = outer.subGraph
        let member = SubgraphNode(context: context)
        graph.addNode(member)
        let first = NumberBinaryOperator(context: context)
        member.subGraph.addNode(first)
        member.subGraph.setPublished(true, on: first.inputNumber1)
        let sibling = try graph.duplicateAsClone(member)

        // The sibling's proxy is published on through the outer node, and wired there.
        let siblingProxy = try #require(sibling.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == first.inputNumber1.id })
        graph.setPublished(true, on: siblingProxy)
        let outerProxy = try #require(outer.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == siblingProxy.id })
        let upstream = NumberBinaryOperator(context: context)
        root.addNode(upstream)
        _ = try #require(root.connect(upstream.outputNumber, to: outerProxy))
        try #require(sibling.subGraph.node(forID: first.id) as? NumberBinaryOperator).inputNumber1.value = 7

        let undoManager = UndoManager()
        root.undoManager = undoManager
        graph.undoManager = undoManager
        member.subGraph.undoManager = undoManager
        sibling.subGraph.undoManager = undoManager
        edit(undoManager) { member.subGraph.setPublished(false, on: first.inputNumber1) }

        #expect(!sibling.ports.contains { $0.id == siblingProxy.id })
        #expect(!outer.ports.contains { $0.id == outerProxy.id })
        #expect(upstream.outputNumber.connections.isEmpty)
        #expect(root.connections.isEmpty)

        func expectPutBack(sourceLocation: SourceLocation = #_sourceLocation) throws
        {
            let proxy = try #require(sibling.ports.first { $0.id == siblingProxy.id }, sourceLocation: sourceLocation)
            #expect(proxy.published, sourceLocation: sourceLocation)
            let over = try #require(outer.ports.first { $0.id == outerProxy.id }, sourceLocation: sourceLocation)
            #expect(over.connections.count == 1, sourceLocation: sourceLocation)
            #expect(upstream.outputNumber.connections.count == 1, sourceLocation: sourceLocation)
            let inner = sibling.subGraph.node(forID: first.id) as? NumberBinaryOperator
            #expect(inner?.inputNumber1.value == 7, sourceLocation: sourceLocation)
        }

        undoManager.undo()
        try expectPutBack()

        undoManager.redo()
        #expect(!outer.ports.contains { $0.id == outerProxy.id })
        #expect(upstream.outputNumber.connections.isEmpty)

        undoManager.undo()
        try expectPutBack()
    }

    @Test("A node a sync puts another in place of is released once its undo step is gone and its graph's lifecycle review is taken")
    @MainActor
    func replacedNodeIsReleased() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let pair = try makePair(context: harness.context)
        try harness.graphRenderer(for: pair.graph).startExecution()
        try harness.execute(pair.graph, frameNumber: 0)
        try harness.execute(pair.graph, frameNumber: 1)

        // A settings change: the sibling's node is made again under its ids.
        let expression = MathExpressionNode(context: harness.context, expression: "x + y")
        pair.source.addNode(expression)
        pair.graph.syncCloneSets(editedIn: pair.source)
        weak var retiredNode: Node?
        do
        {
            retiredNode = pair.counterpart(of: expression)
            expression.stringExpression = "x * y"
            pair.graph.syncCloneSets(editedIn: pair.source)
        }
        #expect(pair.counterpart(of: expression) !== retiredNode)
        // The step that would put the node back holds it, and it waits in its
        // graph's review, as any node taken out of a graph does, until the
        // renderer next reviews that graph.
        pair.undoManager.removeAllActions()
        _ = pair.target.takeNodesAwaitingLifecycleReview()
        for frame in 2..<5 { try harness.execute(pair.graph, frameNumber: frame) }

        #expect(retiredNode == nil)
    }
}

// MARK: - Published groups

extension CloneSetTests
{
    @Test("A published slider at every level above writes a sibling's live inner port after a sync put another node under its proxy")
    @MainActor
    func publishedGroupsFollowASync() throws
    {
        guard let context = makeContext() else { return }
        let root = Graph(context: context)
        let outer = SubgraphNode(context: context)
        root.addNode(outer)
        let member = SubgraphNode(context: context)
        outer.subGraph.addNode(member)
        let expression = MathExpressionNode(context: context, expression: "x + y")
        member.subGraph.addNode(expression)
        let x = try #require(expression.inputPorts().first { $0.name == "x" })
        member.subGraph.setPublished(true, on: x)

        // The sibling's proxy is published up to the root.
        let sibling = try outer.subGraph.duplicateAsClone(member)
        let siblingProxyID = try #require(sibling.ports.first { $0.kind == .Inlet }).id
        outer.subGraph.setPublished(true, on: try #require(outer.subGraph.nodePort(forID: siblingProxyID)))
        let outerProxyID = try #require(outer.ports.first { $0.kind == .Inlet }).id
        root.setPublished(true, on: try #require(root.nodePort(forID: outerProxyID)))

        // A settings change: the sibling's node is made again under its ids.
        let before = try #require(counterpart(of: expression, in: sibling))
        expression.stringExpression = "x * y"
        CloneSetModel.syncSiblings(of: member)

        let copy = try #require(counterpart(of: expression, in: sibling))
        #expect(copy !== before)
        let copyX = try #require(copy.inputPorts().first { $0.name == "x" })
        let parameter = try #require(copyX.parameter as AnyObject?)
        let siblingProxy = try #require(outer.subGraph.nodePort(forID: siblingProxyID))
        let outerProxy = try #require(root.nodePort(forID: outerProxyID))
        #expect(siblingProxy.published && outerProxy.published)
        #expect((siblingProxy.parameter as AnyObject?) === parameter)
        #expect(outer.subGraph.publishedParameterGroup.params.contains { ($0 as AnyObject) === parameter })
        #expect((outerProxy.parameter as AnyObject?) === parameter)
        #expect(root.publishedParameterGroup.params.contains { ($0 as AnyObject) === parameter })
    }
}

// MARK: - In place

extension CloneSetTests
{
    @Test("A port published and named, and an unpublished inlet given a value, take it in the sibling in place, undoably")
    @MainActor
    func portStateIsTakenInPlace() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        let secondCopy = try #require(pair.counterpart(of: pair.member.second))

        edit(pair.undoManager) {
            pair.source.setPublished(true, on: pair.member.second.inputNumber2)
            pair.source.setPublishedName("Offset", on: pair.member.second.inputNumber2)
            pair.member.first.inputNumber2.value = 4
        }

        #expect(pair.counterpart(of: pair.member.second) === secondCopy)
        #expect(pair.counterpart(of: pair.member.first) === firstCopy)
        #expect(secondCopy.inputNumber2.published)
        #expect(secondCopy.inputNumber2.publishedName == "Offset")
        #expect(firstCopy.inputNumber2.value == 4)
        #expect(pair.sibling.ports.contains { ($0 as? any ProxyPortProtocol)?.innerPortID == pair.member.second.inputNumber2.id })

        pair.undoManager.undo()
        #expect(pair.counterpart(of: pair.member.second) === secondCopy)
        #expect(!secondCopy.inputNumber2.published)
        #expect(firstCopy.inputNumber2.value == 0)
        #expect(!pair.sibling.ports.contains { ($0 as? any ProxyPortProtocol)?.innerPortID == pair.member.second.inputNumber2.id })
    }

    @Test("Publishing a port inside a plain nested sub graph patches inside it, the nested node and its other nodes left in place")
    @MainActor
    func nestedPublishPatchesInside() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let nestedCopy = try #require(pair.counterpart(of: pair.member.nested))
        let innerCopy = try #require(pair.counterpart(of: pair.member.nestedInner))
        let other = NumberBinaryOperator(context: context)
        pair.member.nested.subGraph.addNode(other)
        pair.sync()
        let otherCopy = try #require(pair.counterpart(of: other))

        edit(pair.undoManager) { pair.member.nested.subGraph.setPublished(true, on: pair.member.nestedInner.inputNumber1) }

        #expect(pair.counterpart(of: pair.member.nested) === nestedCopy)
        #expect(pair.counterpart(of: pair.member.nestedInner) === innerCopy)
        #expect(pair.counterpart(of: other) === otherCopy)
        #expect(innerCopy.inputNumber1.published)
        #expect(nestedCopy.ports.contains { ($0 as? any ProxyPortProtocol)?.innerPortID == pair.member.nestedInner.inputNumber1.id })

        // And its proxy published on, up to the member's edge.
        let proxy = try #require(pair.member.nested.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == pair.member.nestedInner.inputNumber1.id })
        edit(pair.undoManager) { pair.source.setPublished(true, on: proxy) }
        #expect(pair.counterpart(of: pair.member.nested) === nestedCopy)
        let copyProxy = try #require(nestedCopy.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == pair.member.nestedInner.inputNumber1.id })
        #expect(copyProxy.published)
        #expect(pair.sibling.ports.contains { ($0 as? any ProxyPortProtocol)?.innerPortID == copyProxy.id })
    }

    @Test("A node made again leaves the inlet it feeds holding what it has until the replacement sends")
    @MainActor
    func replacementLeavesTheFedInletAlone() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let expression = MathExpressionNode(context: context, expression: "x + y")
        pair.source.addNode(expression)
        let fed = NumberBinaryOperator(context: context)
        pair.source.addNode(fed)
        let output = try #require(expression.outputPorts().first)
        _ = try #require(pair.source.connect(output, to: fed.inputNumber1))
        pair.sync()

        let fedCopy = try #require(pair.counterpart(of: fed))
        fedCopy.inputNumber1.value = 9
        let before = try #require(pair.counterpart(of: expression))
        expression.stringExpression = "x * y"
        pair.sync()

        #expect(pair.counterpart(of: expression) !== before)
        #expect(pair.counterpart(of: fed) === fedCopy)
        #expect(fedCopy.inputNumber1.value == 9)
        #expect(pair.target.connections.count == 2)
        #expect(pair.target.connections.contains { $0.outletPort === pair.counterpart(of: expression)?.outputPorts().first && $0.inletPort === fedCopy.inputNumber1 })
    }

    @Test("A canvas standing inside a sibling's nested sub graph follows it through a sync that takes it and the undo that brings it back")
    @MainActor
    func canvasInsideNestedFollowsUndo() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let nestedCopy = try #require(pair.counterpart(of: pair.member.nested))
        let canvas = GraphCanvasContext(rootGraph: pair.graph)
        canvas.enter(pair.sibling)
        canvas.enter(nestedCopy)
        #expect(canvas.currentGraph === nestedCopy.subGraph)

        edit(pair.undoManager) { pair.source.delete(node: pair.member.nested) }
        #expect(pair.counterpart(of: pair.member.nested) == nil)

        pair.undoManager.undo()
        let restored = try #require(pair.counterpart(of: pair.member.nested))
        #expect(canvas.entries.last === restored)
        #expect(canvas.currentGraph === restored.subGraph)

        pair.undoManager.redo()
        #expect(pair.counterpart(of: pair.member.nested) == nil)
    }
}
