import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// What a clone set must do for its user, whatever model keeps the members
/// identical. This file is the same on every branch that implements clone
/// sets; what it cannot say without naming the model, finding a node's
/// counterpart in another member and syncing one member's siblings, it asks
/// of `CloneSetModel`, which each branch provides. Behaviour a model gives up
/// by design is listed in `CloneSetModel.divergences` and its test runs as a
/// known issue there. Tests of a model's own machinery live in CloneSetTests.
///
/// Nodes are found again by id after every sync rather than held across it:
/// a model is free to replace node objects as it brings members in line.
@Suite("Clone Set Contract")
struct CloneSetContractTests
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

    private func decode(_ data: Data, context: Context) throws -> Graph
    {
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        return try decoder.decode(Graph.self, from: data)
    }

    private func roundTrip(_ graph: Graph, context: Context) throws -> Graph
    {
        try decode(JSONEncoder().encode(graph), context: context)
    }

    /// Saves the way the editor does, once its edits have synced.
    private func save(_ graph: Graph) throws -> Data
    {
        graph.syncCloneSets()
        return try JSONEncoder().encode(graph)
    }

    /// Every member of the pair's set matches it, as each does once the edits
    /// made in any of them have synced.
    private func membersAreInStep(_ pair: PairFixture) -> Bool
    {
        CloneSetModel.isInStep(pair.member.member) && CloneSetModel.isInStep(pair.sibling)
    }

    private func memberEntries(in data: Data) throws -> [[String: Any]]
    {
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let nodeMap = try #require(object["nodeMap"] as? [[String: Any]])
        return nodeMap.compactMap { $0["value"] as? [String: Any] }.filter { $0["cloneSetID"] != nil }
    }

    /// A member as it stands: its full encoding and the node objects it
    /// holds, so a sync that changed nothing can be told from one that did.
    private struct MemberSnapshot: Equatable
    {
        let encoded: Data
        let nodes: [ObjectIdentifier]
    }

    private func snapshot(_ member: SubgraphNode) throws -> MemberSnapshot
    {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return MemberSnapshot(encoded: try encoder.encode(member),
                              nodes: member.subGraph.nodesRecursive().map(ObjectIdentifier.init))
    }

    private func node<T: Node>(withID id: UUID, in member: SubgraphNode, as type: T.Type = T.self) -> T?
    {
        member.subGraph.nodesRecursive().first { $0.id == id } as? T
    }

    private func proxy(in member: SubgraphNode, over innerPort: Fabric.Port) -> Fabric.Port?
    {
        member.ports.first { ($0 as? any ProxyPortProtocol)?.innerPortID == innerPort.id }
    }

    /// Runs `body` as a known issue where the model under test gives up
    /// `divergence` by design, and as an ordinary test everywhere else.
    private func expecting(_ divergence: CloneSetDivergence, _ body: () throws -> Void) rethrows
    {
        if CloneSetModel.divergences.contains(divergence)
        {
            withKnownIssue("\(CloneSetModel.name) gives this up by design: \(divergence)") { try body() }
        }
        else
        {
            try body()
        }
    }

    /// A member with two wired inner nodes, one published inlet and a nested
    /// subgraph, so cloning is checked at every level.
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

    /// A two-member set plus an undo manager on every graph involved.
    private struct PairFixture
    {
        let member: MemberFixture
        let sibling: SubgraphNode
        let undoManager: UndoManager

        var graph: Graph { member.graph }
        var source: Graph { member.member.subGraph }
        var target: Graph { sibling.subGraph }

        func sync() { CloneSetModel.syncSiblings(of: member.member) }

        /// Makes `body` one undo group of its own, as the editor's event loop
        /// does, closing it with the sync that follows. Without a run loop,
        /// edits would otherwise share one group that never closes; one an
        /// earlier edit left open is closed first, as its event's end would.
        @discardableResult
        func edit<T>(_ body: () throws -> T) rethrows -> T
        {
            undoManager.groupsByEvent = false
            while undoManager.groupingLevel > 0 { undoManager.endUndoGrouping() }
            undoManager.beginUndoGrouping()
            defer { undoManager.endUndoGrouping() }
            return try body()
        }

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

        /// The source member's own node, as it is now.
        func current<T: Node>(_ node: T) -> T?
        {
            member.member.subGraph.nodesRecursive().first { $0.id == node.id } as? T
        }

        /// The sibling's node for one of the source member's, at any depth.
        func counterpart<T: Node>(of node: T) -> T?
        {
            CloneSetModel.counterpart(of: node, from: member.member, in: sibling)
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
}

/// Behaviour a clone set model may give up by design. Each model lists its
/// own in `CloneSetModel.divergences`.
enum CloneSetDivergence: String, Hashable, CustomStringConvertible
{
    /// A sync replaces the sibling's node objects, so whatever they held at
    /// runtime starts over.
    case siblingNodesAreReplaced

    var description: String { rawValue }
}

// MARK: - Sets

extension CloneSetContractTests
{
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

    @Test("Duplicate as Clone starts a set on the root graph and copies the member whole")
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

        #expect(copy.id != fixture.member.id)
        #expect(copy.subGraph !== fixture.member.subGraph)
        #expect(copy.subGraph.id != fixture.member.subGraph.id)
        #expect(copy.subGraph.nodesRecursive().count == fixture.member.subGraph.nodesRecursive().count)
        for node in fixture.member.subGraph.nodesRecursive()
        {
            let copied = try #require(CloneSetModel.counterpart(of: node, from: fixture.member, in: copy), "\(node)")
            #expect(copied !== node)
            #expect(type(of: copied) == type(of: node))
        }

        let copiedFirst = try #require(CloneSetModel.counterpart(of: fixture.first, from: fixture.member, in: copy))
        let copiedSecond = try #require(CloneSetModel.counterpart(of: fixture.second, from: fixture.member, in: copy))
        let copiedNested = try #require(CloneSetModel.counterpart(of: fixture.nested, from: fixture.member, in: copy))
        let copiedNestedInner = try #require(CloneSetModel.counterpart(of: fixture.nestedInner, from: fixture.member, in: copy))
        #expect(copiedFirst.inputNumber1.published)
        #expect(copiedFirst.inputNumber1.publishedName == "Amount")
        #expect(copy.subGraph.connections.count == 1)
        #expect(copy.subGraph.connections.first?.outletPort === copiedFirst.outputNumber)
        #expect(copy.subGraph.connections.first?.inletPort === copiedSecond.inputNumber1)
        #expect(copiedNestedInner.graph === copiedNested.subGraph)
        #expect(proxy(in: copy, over: copiedFirst.inputNumber1) != nil)
    }

    @Test("Sets, members and names survive a save, and the loaded members still sync")
    func setsRoundTrip() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let copy = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)
        try fixture.graph.renameCloneSet(setID, to: "Lyric Panel")

        let decoded = try roundTrip(fixture.graph, context: context)

        #expect(decoded.cloneSet(for: setID)?.name == "Lyric Panel")
        let members = decoded.cloneSetMembers(of: setID)
        #expect(members.map(\.id) == [fixture.member.id, copy.id])
        #expect(members[1].subGraph.nodesRecursive().count == fixture.member.subGraph.nodesRecursive().count)

        members[0].subGraph.addNode(NumberBinaryOperator(context: context))
        CloneSetModel.syncSiblings(of: members[0])
        #expect(members[1].subGraph.nodes.count == 4)
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

    @Test("A pasted member is an ordinary subgraph")
    func pastedMemberCarriesNoLinks() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        _ = try pair.source.duplicateAsClone(pair.member.nested)

        pair.graph.copyNodesToPasteboard([pair.member.member])
        let pasted = pair.graph.pasteNodesFromPasteboard()

        let pastedMember = try #require(pasted.first as? SubgraphNode)
        #expect(pastedMember.cloneSetID == nil)
        #expect(pastedMember.subGraph.subgraphNodesRecursive().allSatisfy { $0.cloneSetID == nil })
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

    @Test("Unlink leaves the set and gives the nested sets it takes a set of their own, undoably")
    func unlinkDetaches() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)

        let nestedSibling = try fixture.member.subGraph.duplicateAsClone(fixture.nested)
        let nestedSetID = try #require(fixture.nested.cloneSetID)
        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)
        #expect(fixture.graph.cloneSets.count == 2)
        #expect(fixture.graph.cloneSetMembers(of: nestedSetID).count == 4)

        // Without a run loop every registration so far would share one undo group; the unlink gets its own.
        let undoManager = UndoManager()
        fixture.graph.undoManager = undoManager
        try fixture.graph.unlinkClone(sibling)

        #expect(sibling.cloneSetID == nil)
        #expect(fixture.member.cloneSetID == setID)
        #expect(fixture.graph.cloneSetMembers(of: setID).map(\.id) == [fixture.member.id])
        #expect(sibling.subGraph.nodes.count == 4)

        let detached = sibling.subGraph.subgraphNodesRecursive().filter { $0.cloneSetID != nil }
        #expect(detached.count == 2)
        let detachedSetID = try #require(detached.first?.cloneSetID)
        #expect(detachedSetID != nestedSetID)
        #expect(detached.allSatisfy { $0.cloneSetID == detachedSetID })
        #expect(fixture.graph.cloneSet(for: detachedSetID)?.name == "Set C")
        #expect(fixture.graph.cloneSetMembers(of: nestedSetID).map(\.id) == [fixture.nested.id, nestedSibling.id])

        // The detached pair is a working set.
        detached[0].subGraph.addNode(NumberBinaryOperator(context: context))
        CloneSetModel.syncSiblings(of: detached[0])
        #expect(fixture.graph.cloneSetMembers(of: detachedSetID).allSatisfy { $0.subGraph.nodes.count == 2 })
        #expect(fixture.graph.cloneSetMembers(of: nestedSetID).allSatisfy { $0.subGraph.nodes.count == 1 })

        undoManager.undo()
        #expect(sibling.cloneSetID == setID)
        #expect(fixture.graph.cloneSetMembers(of: nestedSetID).count == 4)
        #expect(fixture.graph.cloneSet(for: detachedSetID) == nil)

        undoManager.redo()
        #expect(sibling.cloneSetID == nil)
        #expect(fixture.graph.cloneSet(for: detachedSetID) != nil)
    }

    @Test("A set with no members left is dropped on save")
    func emptySetsAreDropped() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)

        try fixture.graph.unlinkClone(sibling)
        try fixture.graph.unlinkClone(fixture.member)
        #expect(fixture.graph.cloneSet(for: setID) != nil)

        let decoded = try roundTrip(fixture.graph, context: context)
        #expect(decoded.cloneSets.isEmpty)
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

        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.sync()
        #expect(pair.target.nodes.count == 3)
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
        #expect(throws: FabricError.self) { try CloneSetModel.syncMember(stranger, from: fixture.member) }
        #expect(fixture.graph.nodes.contains { $0 === sibling })
    }
}

// MARK: - Names and status

extension CloneSetContractTests
{
    @Test("Sets are named in sequence and renamed undoably; an empty name goes back to a system one")
    func namesAndRenames() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)
        #expect(fixture.graph.cloneSet(for: setID)?.name == "Set A")

        let other = SubgraphNode(context: context)
        fixture.graph.addNode(other)
        _ = try fixture.graph.duplicateAsClone(other)
        let otherSetID = try #require(other.cloneSetID)
        #expect(fixture.graph.cloneSet(for: otherSetID)?.name == "Set B")

        _ = try fixture.member.subGraph.duplicateAsClone(fixture.nested)
        let nestedSetID = try #require(fixture.nested.cloneSetID)
        #expect(fixture.graph.cloneSet(for: nestedSetID)?.name == "Set C")

        let undoManager = UndoManager()
        fixture.graph.undoManager = undoManager
        try fixture.graph.renameCloneSet(setID, to: "  Lyric Panel ")
        #expect(fixture.graph.cloneSet(for: setID)?.name == "Lyric Panel")
        #expect(sibling.subtitle == "Lyric Panel")
        #expect(fixture.member.cloneSetInfo?.name == "Lyric Panel")

        undoManager.undo()
        #expect(sibling.subtitle == "Set A")
        undoManager.redo()
        #expect(sibling.subtitle == "Lyric Panel")

        // Empty goes back to the lowest free system name; A is free again.
        try fixture.graph.renameCloneSet(setID, to: "   ")
        #expect(sibling.subtitle == "Set A")
    }

    @Test("Members show the set name as their subtitle and report a linked status until they leave")
    func subtitleAndLinkedStatus() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        #expect(fixture.member.subtitle == nil)
        #expect(fixture.member.status == nil)

        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        let otherSibling = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)
        #expect(fixture.member.subtitle == "Set A")
        #expect(fixture.member.cloneSetInfo == CloneSetInfo(setID: setID, name: "Set A", memberCount: 3))
        let status = try #require(sibling.status)
        #expect(status == .linked("Clone set Set A, 3 members. Edits here reach every member."))
        #expect(status.description == "Linked: Clone set Set A, 3 members. Edits here reach every member.")
        #expect(NodeStatus.warning("w") > status)

        fixture.graph.delete(node: otherSibling)
        #expect(fixture.member.status?.message == "Clone set Set A, 2 members. Edits here reach every member.")

        try fixture.graph.unlinkClone(sibling)
        #expect(sibling.status == nil)
        #expect(sibling.subtitle == nil)
        #expect(fixture.member.status?.message == "Clone set Set A, 1 member. Edits here reach every member.")
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

    @Test("Removing an outer member refreshes the badges of the nested set it took with it")
    @MainActor
    func nestedSetBadgesFollowOuterMembership() async throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        _ = try pair.source.duplicateAsClone(pair.member.nested)
        pair.graph.syncCloneSets()
        let nestedSetID = try #require(pair.member.nested.cloneSetID)
        #expect(pair.graph.cloneSetMembers(of: nestedSetID).count == 4)

        let nested = try #require(pair.current(pair.member.nested))
        let nestedViewModel = pair.source.viewModel(for: nested)
        for _ in 0..<50 where nestedViewModel.status?.message.contains("4 members") != true
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(nestedViewModel.status?.message.contains("4 members") == true)

        pair.graph.delete(node: pair.sibling)

        for _ in 0..<50 where nestedViewModel.status?.message.contains("2 members") != true
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(nestedViewModel.status?.message.contains("2 members") == true)
    }
}

// MARK: - Sync

extension CloneSetContractTests
{
    @Test("Adding and wiring a node in one member appears in the sibling, with no undo step of the sync's own")
    func addedNodeAppearsInSibling() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let added = NumberBinaryOperator(context: context)
        added.offset = CGSize(width: 300, height: 40)
        pair.source.addNode(added)
        _ = try #require(pair.source.connect(pair.member.second.outputNumber, to: added.inputNumber2))

        pair.syncExpectingNoUndo()

        let addedCopy = try #require(pair.counterpart(of: added))
        let secondCopy = try #require(pair.counterpart(of: pair.member.second))
        #expect(addedCopy !== added)
        #expect(addedCopy.offset == added.offset)
        #expect(pair.target.ownerNode === pair.sibling)
        #expect(pair.target.nodes.count == 4)
        #expect(pair.target.connections.count == 2)
        #expect(pair.target.connections.contains {
            $0.outletPort === secondCopy.outputNumber && $0.inletPort === addedCopy.inputNumber2
        })
    }

    @Test("Deleting a node in one member removes it, its wires and its proxies from the sibling")
    func deletedNodeLeavesSibling() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.source.delete(node: pair.member.first)
        pair.syncExpectingNoUndo()

        #expect(pair.counterpart(of: pair.member.first) == nil)
        #expect(pair.target.nodes.count == 2)
        #expect(pair.target.connections.isEmpty)
        #expect(pair.sibling.ports.contains { $0 is any ProxyPortProtocol } == false)
        #expect(pair.member.member.ports.contains { $0 is any ProxyPortProtocol } == false)
    }

    @Test("Wires and their enabled state follow the source")
    func connectionsFollow() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let existing = try #require(pair.source.connections.first)

        #expect(pair.source.disconnect(existing))
        let rewired = try #require(pair.source.connect(pair.member.first.outputNumber, to: pair.member.second.inputNumber2))
        #expect(pair.source.setConnection(rewired, active: false))

        pair.sync()

        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        let secondCopy = try #require(pair.counterpart(of: pair.member.second))
        #expect(pair.target.connections.count == 1)
        let copiedConnection = try #require(pair.target.connections.first)
        #expect(copiedConnection.outletPort === firstCopy.outputNumber)
        #expect(copiedConnection.inletPort === secondCopy.inputNumber2)
        #expect(copiedConnection.active == false)

        #expect(pair.source.setConnection(rewired, active: true))
        pair.sync()
        #expect(pair.target.connections.first?.active == true)
    }

    @Test("Publishing in the source adds a proxy on the sibling; unpublishing removes it")
    func publishedPortsFollow() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.member.second.outputNumber.published = true
        pair.member.second.outputNumber.publishedName = "Result"
        pair.member.first.inputNumber1.published = false
        pair.source.rebuildPublishedParameterGroup()

        pair.sync()

        let secondCopy = try #require(pair.counterpart(of: pair.member.second))
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        #expect(secondCopy.outputNumber.published)
        #expect(secondCopy.outputNumber.publishedName == "Result")
        #expect(firstCopy.inputNumber1.published == false)
        #expect(proxy(in: pair.sibling, over: secondCopy.outputNumber) != nil)
        #expect(proxy(in: pair.sibling, over: firstCopy.inputNumber1) == nil)
    }

    @Test("Published inlet values stay per member; unpublished values follow the source")
    func valuesSplitAtThePublishBoundary() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        let secondCopy = try #require(pair.counterpart(of: pair.member.second))

        pair.member.first.inputNumber1.value = 1       // published: per member
        firstCopy.inputNumber1.value = 5
        pair.member.second.inputNumber2.value = 7      // unpublished, unwired: design
        secondCopy.inputNumber2.value = 8
        pair.member.first.inputNumber2.value = 9
        firstCopy.inputNumber2.value = 9

        pair.sync()

        let syncedFirst = try #require(pair.counterpart(of: pair.member.first))
        let syncedSecond = try #require(pair.counterpart(of: pair.member.second))
        #expect(pair.current(pair.member.first)?.inputNumber1.value == 1)
        #expect(syncedFirst.inputNumber1.value == 5)
        #expect(syncedSecond.inputNumber2.value == 7)
        #expect(syncedFirst.inputNumber2.value == 9)
        #expect(syncedSecond.inputNumber1.connections.count == 1)
        let siblingProxy = try #require(proxy(in: pair.sibling, over: syncedFirst.inputNumber1) as? NodePort<Float>)
        #expect(siblingProxy.value == 5)
    }

    @Test("A sibling keeps its proxies through a sync, with the parent's wires and published state on them")
    func proxiesSurviveSync() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let upstream = NumberBinaryOperator(context: context)
        pair.graph.addNode(upstream)
        let siblingProxy = try #require(pair.sibling.ports.first { $0 is any ProxyPortProtocol } as? NodePort<Float>)
        let proxyID = siblingProxy.id
        _ = try #require(pair.graph.connect(upstream.outputNumber, to: siblingProxy))
        siblingProxy.published = true
        siblingProxy.publishedName = "Gain"
        #expect(pair.graph.connections.count == 1)

        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.syncExpectingNoUndo()

        let kept = try #require(pair.sibling.ports.first { $0 is any ProxyPortProtocol })
        #expect(kept === siblingProxy)
        #expect(kept.id == proxyID)
        #expect(kept.published)
        #expect(kept.publishedName == "Gain")
        #expect(pair.graph.connections.count == 1)
        #expect(pair.graph.connections.first?.inletPort === siblingProxy)
        #expect(siblingProxy.connections.count == 1)

        // The proxy reads and feeds the sibling's inner port as it is now.
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        siblingProxy.value = 3
        #expect(firstCopy.inputNumber1.value == 3)
        firstCopy.inputNumber1.value = 4
        #expect(siblingProxy.value == 4)
    }

    @Test("A proxy published further up follows a sync of the nested member beneath it")
    func publishedChainSurvivesNestedSync() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        // The nested member's published inlet, published on through the outer node.
        fixture.nestedInner.inputNumber1.published = true
        fixture.nested.subGraph.rebuildPublishedParameterGroup()
        let nestedProxy = try #require(proxy(in: fixture.nested, over: fixture.nestedInner.inputNumber1))
        nestedProxy.published = true
        fixture.member.subGraph.rebuildPublishedParameterGroup()
        let outerProxy = try #require(proxy(in: fixture.member, over: nestedProxy) as? NodePort<Float>)

        // A sibling of the nested member beside it, edited.
        let elsewhere = try fixture.member.subGraph.duplicateAsClone(fixture.nested)
        elsewhere.subGraph.addNode(NumberBinaryOperator(context: context))
        CloneSetModel.syncSiblings(of: elsewhere)

        #expect(fixture.nested.subGraph.nodes.count == 2)
        #expect(proxy(in: fixture.member, over: nestedProxy) === outerProxy)
        #expect(fixture.nested.ports.first { $0 is any ProxyPortProtocol } === nestedProxy)
        let inner = try #require(node(withID: fixture.nestedInner.id, in: fixture.nested, as: NumberBinaryOperator.self))
        outerProxy.value = 6
        #expect(inner.inputNumber1.value == 6)
    }

    @Test("Every member's proxies are ports of their own, each found by its id")
    func proxiesAreDistinctAcrossMembers() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.member.second.inputNumber2.published = true
        pair.source.rebuildPublishedParameterGroup()
        pair.sync()

        let secondCopy = try #require(pair.counterpart(of: pair.member.second))
        let sourceProxy = try #require(proxy(in: pair.member.member, over: pair.member.second.inputNumber2))
        let siblingProxy = try #require(proxy(in: pair.sibling, over: secondCopy.inputNumber2))
        #expect(sourceProxy !== siblingProxy)
        #expect(sourceProxy.id != siblingProxy.id)
        #expect(pair.graph.nodePort(forID: sourceProxy.id) === sourceProxy)
        #expect(pair.graph.nodePort(forID: siblingProxy.id) === siblingProxy)
    }

    @Test("Unpublishing inside a member takes the parent's wire onto its proxy with it")
    @MainActor
    func unpublishingInsideMemberTakesTheParentWire() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let siblingProxy = try #require(pair.sibling.ports.first { $0.kind == .Inlet && $0.displayName == "Amount" })
        let upstream = NumberBinaryOperator(context: context)
        pair.graph.addNode(upstream)
        let wire = try #require(pair.graph.connect(upstream.outputNumber, to: siblingProxy))
        let inner = try #require(pair.counterpart(of: pair.member.first))

        pair.target.setPublished(false, on: inner.inputNumber1)

        #expect(!pair.sibling.ports.contains { $0 === siblingProxy })
        #expect(!pair.graph.connections.contains { $0 === wire })
        #expect(upstream.outputNumber.connections.isEmpty)

        pair.target.setPublished(true, on: inner.inputNumber1)
        let rebuilt = try #require(proxy(in: pair.sibling, over: inner.inputNumber1))
        #expect(rebuilt.connections.isEmpty)
    }

    @Test("Undoing an unpublish that reached a sibling puts the parent's wire back onto the sibling's proxy")
    @MainActor
    func undoingASyncedUnpublishRestoresTheSiblingWire() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let siblingProxy = try #require(pair.sibling.ports.first { $0.kind == .Inlet && $0.displayName == "Amount" })
        let upstream = NumberBinaryOperator(context: context)
        pair.graph.addNode(upstream)
        _ = try #require(pair.graph.connect(upstream.outputNumber, to: siblingProxy))

        pair.edit { pair.source.setPublished(false, on: pair.member.first.inputNumber1) }
        #expect(upstream.outputNumber.connections.isEmpty)

        pair.undoManager.undo()
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        let restored = try #require(proxy(in: pair.sibling, over: firstCopy.inputNumber1))
        #expect(upstream.outputNumber.connections.count == 1)
        #expect(upstream.outputNumber.connections.first?.inletPort === restored)
    }

    @Test("Unpublishing a port in one member makes its value design again, the edited member's for every member")
    @MainActor
    func unpublishedValueIsDesign() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        pair.member.first.inputNumber1.value = 1
        try #require(pair.counterpart(of: pair.member.first)).inputNumber1.value = 9

        pair.edit { pair.source.setPublished(false, on: pair.member.first.inputNumber1) }

        #expect(pair.current(pair.member.first)?.inputNumber1.value == 1)
        #expect(pair.counterpart(of: pair.member.first)?.inputNumber1.value == 1)
    }

    @Test("Undoing an unpublish inside a member puts the parent's wire back onto its proxy")
    @MainActor
    func undoingAnUnpublishInsideAMemberRestoresTheWire() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let siblingProxy = try #require(pair.sibling.ports.first { $0.kind == .Inlet && $0.displayName == "Amount" })
        let upstream = NumberBinaryOperator(context: context)
        pair.graph.addNode(upstream)
        _ = try #require(pair.graph.connect(upstream.outputNumber, to: siblingProxy))
        let inner = try #require(pair.counterpart(of: pair.member.first))

        pair.edit { pair.target.setPublished(false, on: inner.inputNumber1) }
        #expect(upstream.outputNumber.connections.isEmpty)

        pair.undoManager.undo()
        let innerNow = try #require(pair.counterpart(of: pair.member.first))
        let restored = try #require(proxy(in: pair.sibling, over: innerNow.inputNumber1))
        #expect(upstream.outputNumber.connections.count == 1)
        #expect(upstream.outputNumber.connections.first?.inletPort === restored)
        #expect(pair.current(pair.member.first)?.inputNumber1.published == true)
    }

    @Test("After a sync the renderer runs the sibling's wired nodes, and any node the sibling no longer holds is stopped")
    func siblingNodesRunAfterSync() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let renderer = GraphRenderer(context: context, graph: pair.graph)
        try renderer.startExecution()
        let before = pair.target.nodesRecursive()
        let wiredBefore = pair.target.nodes.filter { !$0.inputNodes.isEmpty || !$0.outputNodes.isEmpty }
        #expect(wiredBefore.count == 2)
        #expect(wiredBefore.allSatisfy { $0.executionState == .started })

        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.sync()
        try renderer.synchronizeLifecycle()

        let after = pair.target.nodesRecursive()
        let retired = before.filter { old in !after.contains { $0 === old } }
        #expect(retired.allSatisfy { $0.executionState == .disabled }, "\(retired.map { "\($0): \($0.executionState)" })")
        let wiredAfter = pair.target.nodes.filter { !$0.inputNodes.isEmpty || !$0.outputNodes.isEmpty }
        #expect(wiredAfter.count == 2)
        #expect(wiredAfter.allSatisfy { $0.executionState == .started })
        try renderer.stopExecution()
    }

    @Test("A Deferred member's renderer follows its sub graph through a sync")
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
        CloneSetModel.syncSiblings(of: deferred)

        #expect(sibling.subGraph.nodes.count == 2)
        #expect(sibling.childGraphRenderer?.graph === sibling.subGraph)
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
        #expect(firstCopy.offset == CGSize(width: -120, height: 64))
        #expect(firstCopy.userName == "Gain")
        #expect(pair.target.notes.count == 1)
        #expect(pair.target.notes.first?.note == note.note)
        #expect(pair.target.notes.first?.rect == note.rect)
    }

    @Test("A settings change reaches the sibling, ports rebuilt or not, and the wire into a rebuilt port follows")
    func settingsChangesFollow() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let sampler = SampleAndHoldNode(context: context)
        sampler.strategy = PortType.Float.rawValue
        pair.source.addNode(sampler)
        let inlet = try #require(sampler.findPort(named: "inputValue", as: Port.self))
        _ = try #require(pair.source.connect(pair.member.second.outputNumber, to: inlet))
        let expression = MathExpressionNode(context: context, expression: "sin(x) + y")
        pair.source.addNode(expression)
        pair.sync()
        #expect(pair.counterpart(of: sampler)?.strategy == PortType.Float.rawValue)
        #expect(pair.counterpart(of: expression)?.stringExpression == "sin(x) + y")
        #expect(pair.target.connections.count == 2)

        sampler.strategy = PortType.Virtual.rawValue
        expression.stringExpression = "cos(x) + y"
        pair.syncExpectingNoUndo()

        let samplerCopy = try #require(pair.counterpart(of: sampler))
        #expect(samplerCopy.strategy == PortType.Virtual.rawValue)
        #expect(pair.counterpart(of: expression)?.stringExpression == "cos(x) + y")
        #expect(pair.target.connections.count == 2)
        let rebuiltInlet = try #require(samplerCopy.findPort(named: "inputValue", as: Port.self))
        let secondCopy = try #require(pair.counterpart(of: pair.member.second))
        #expect(pair.target.connections.contains {
            $0.outletPort === secondCopy.outputNumber && $0.inletPort === rebuiltInlet
        })
    }

    @Test("Edits inside a nested subgraph reach the sibling's nested subgraph, wires through its proxies included")
    func nestedEditsFollow() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let deepAdded = NumberBinaryOperator(context: context)
        pair.member.nested.subGraph.addNode(deepAdded)
        _ = try #require(pair.member.nested.subGraph.connect(pair.member.nestedInner.outputNumber, to: deepAdded.inputNumber1))
        deepAdded.outputNumber.published = true
        pair.member.nested.subGraph.rebuildPublishedParameterGroup()
        let nestedProxy = try #require(proxy(in: pair.member.nested, over: deepAdded.outputNumber))
        _ = try #require(pair.source.connect(nestedProxy, to: pair.member.second.inputNumber2))

        pair.sync()

        let nestedCopy = try #require(pair.counterpart(of: pair.member.nested))
        let deepCopy = try #require(pair.counterpart(of: deepAdded))
        let nestedInnerCopy = try #require(pair.counterpart(of: pair.member.nestedInner))
        #expect(deepCopy.graph === nestedCopy.subGraph)
        #expect(nestedCopy.subGraph.nodes.count == 2)
        #expect(nestedCopy.subGraph.connections.contains {
            $0.outletPort === nestedInnerCopy.outputNumber && $0.inletPort === deepCopy.inputNumber1
        })
        let nestedProxyCopy = try #require(proxy(in: nestedCopy, over: deepCopy.outputNumber))
        let secondCopy = try #require(pair.counterpart(of: pair.member.second))
        #expect(pair.target.connections.contains {
            $0.outletPort === nestedProxyCopy && $0.inletPort === secondCopy.inputNumber2
        })
    }

    @Test("A nested set inside a member syncs through the outer set, and the nested members keep their own values")
    @MainActor
    func nestedSetsSync() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.member.nestedInner.inputNumber1.published = true
        pair.member.nested.subGraph.rebuildPublishedParameterGroup()
        let nestedSibling = try pair.source.duplicateAsClone(pair.member.nested)
        pair.graph.syncCloneSets()
        let nestedSetID = try #require(pair.member.nested.cloneSetID)
        #expect(pair.graph.cloneSetMembers(of: nestedSetID).count == 4)

        // Per-member values on the nested members, inside both outer members.
        let nestedSiblingInner = try #require(CloneSetModel.counterpart(of: pair.member.nestedInner, from: pair.member.nested, in: nestedSibling))
        let siblingNestedInner = try #require(pair.counterpart(of: pair.member.nestedInner))
        pair.current(pair.member.nestedInner)?.inputNumber1.value = 1
        siblingNestedInner.inputNumber1.value = 2
        nestedSiblingInner.inputNumber1.value = 3

        // An edit inside the nested member reaches every nested member, in both outer members.
        try #require(pair.current(pair.member.nested)).subGraph.addNode(NumberBinaryOperator(context: context))
        pair.graph.syncCloneSets()

        #expect(pair.graph.cloneSetMembers(of: nestedSetID).allSatisfy { $0.subGraph.nodes.count == 2 })
        #expect(pair.current(pair.member.nestedInner)?.inputNumber1.value == 1)
        #expect(pair.counterpart(of: pair.member.nestedInner)?.inputNumber1.value == 2)
        let currentNestedSibling = try #require(pair.current(nestedSibling))
        #expect(CloneSetModel.counterpart(of: pair.member.nestedInner, from: pair.member.nested, in: currentNestedSibling)?.inputNumber1.value == 3)
    }

    @Test("A sync with nothing new to bring leaves the sibling exactly as it was")
    func syncWithNothingNewChangesNothing() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let untouched = try snapshot(pair.sibling)
        pair.sync()
        #expect(try snapshot(pair.sibling) == untouched)

        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.sync()
        let synced = try snapshot(pair.sibling)
        pair.sync()
        #expect(try snapshot(pair.sibling) == synced)
    }

    @Test("An unlinked member no longer follows")
    func unlinkedStopsFollowing() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        try pair.graph.unlinkClone(pair.sibling)

        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.sync()

        #expect(pair.target.nodes.count == 3)
    }
}

// MARK: - Live sync

extension CloneSetContractTests
{
    @Test("Closing the undo group an edit was made in syncs the siblings, and undo and redo sync them again")
    @MainActor
    func undoGroupsSync() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.edit { pair.source.addNode(NumberBinaryOperator(context: context)) }
        #expect(pair.target.nodes.count == 4)

        pair.undoManager.undo()
        #expect(pair.source.nodes.count == 3)
        #expect(pair.target.nodes.count == 3)

        pair.undoManager.redo()
        #expect(pair.source.nodes.count == 4)
        #expect(pair.target.nodes.count == 4)
    }

    @Test("A group closing inside an edit does not sync partway through it")
    @MainActor
    func nestedGroupsWaitForTheEdit() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.edit {
            pair.undoManager.beginUndoGrouping()
            pair.source.addNode(NumberBinaryOperator(context: context))
            pair.undoManager.endUndoGrouping()
            #expect(pair.target.nodes.count == 3)
        }
        #expect(pair.target.nodes.count == 4)
    }

    @Test("Values arriving on published or wired inlets are not edits")
    @MainActor
    func drivenValuesDoNotSync() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let before = try snapshot(pair.sibling)

        pair.member.first.inputNumber1.value = 3       // published: per member
        pair.member.second.inputNumber1.value = 4      // wired: driven
        pair.graph.syncCloneSets(editedIn: pair.source)

        #expect(try snapshot(pair.sibling) == before)
    }

    @Test("An edit that registers no undo reaches the siblings when synced where it was made, not with another member's edit")
    @MainActor
    func unrecordedEditsSyncWhereTheyWereMade() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.member.second.inputNumber2.value = 42                          // no undo step
        pair.edit { pair.graph.addNode(NumberBinaryOperator(context: context)) }   // outside the set
        #expect(pair.counterpart(of: pair.member.second)?.inputNumber2.value != 42)

        pair.graph.syncCloneSets(editedIn: pair.source)
        #expect(pair.counterpart(of: pair.member.second)?.inputNumber2.value == 42)
    }

    @Test("Edits made in turn in each member reach the other")
    @MainActor
    func editsInTurnReachEachOther() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.edit { pair.source.addNode(NumberBinaryOperator(context: context)) }   // in A
        pair.edit { pair.target.addNode(NumberBinaryOperator(context: context)) }   // then in B
        #expect(pair.source.nodes.count == 5)
        #expect(pair.target.nodes.count == 5)

        // A node a sync added is edited like any other.
        let added = try #require(pair.target.nodes.last as? NumberBinaryOperator)
        added.inputNumber2.value = 9
        pair.graph.syncCloneSets(editedIn: pair.target)
        #expect(pair.source.nodes.compactMap { $0 as? NumberBinaryOperator }.contains { $0.inputNumber2.value == 9 })
    }

    @Test("After a wire made in one member syncs into the other, an edit in the first is kept")
    @MainActor
    func editAfterASyncedWireIsKept() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let secondInB = try #require(pair.counterpart(of: pair.member.second))
        let firstInB = try #require(pair.counterpart(of: pair.member.first))

        pair.edit { _ = pair.target.connect(secondInB.outputNumber, to: firstInB.inputNumber2) }
        #expect(pair.source.connections.count == 2)

        pair.edit { pair.target.addNode(NumberBinaryOperator(context: context)) }
        #expect(pair.target.nodes.count == 4)
        #expect(pair.source.nodes.count == 4)
    }

    @Test("A wire and a note a sync adds leave the member in step with its set")
    @MainActor
    func syncedWiresAndNotesKeepMembersInStep() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let secondInB = try #require(pair.counterpart(of: pair.member.second))
        let firstInB = try #require(pair.counterpart(of: pair.member.first))

        pair.edit { _ = pair.target.connect(secondInB.outputNumber, to: firstInB.inputNumber2) }
        pair.edit { pair.target.addNote(Note(note: "Shared", rect: .zero)) }
        #expect(pair.source.notes.count == 1)

        pair.graph.syncCloneSets()
        #expect(membersAreInStep(pair))
    }

    @Test("Edits in a nested member of one sibling and in the other sibling both survive")
    @MainActor
    func nestedAndOuterEditsBothSurvive() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        _ = try pair.source.duplicateAsClone(pair.member.nested)
        pair.graph.syncCloneSets()
        let nestedSetID = try #require(pair.member.nested.cloneSetID)

        // An edit inside a nested member of B, then an edit in A.
        let nestedInB = try #require(pair.counterpart(of: pair.member.nested))
        pair.edit { nestedInB.subGraph.addNode(NumberBinaryOperator(context: context)) }
        pair.edit { pair.source.addNode(NumberBinaryOperator(context: context)) }

        #expect(pair.source.nodes.count == 5)
        #expect(pair.target.nodes.count == 5)
        #expect(pair.graph.cloneSetMembers(of: nestedSetID).count == 4)
        #expect(pair.graph.cloneSetMembers(of: nestedSetID).allSatisfy { $0.subGraph.nodes.count == 2 })
    }

    @Test("An edit inside a nested member reaches the nested set's members and the outer set's")
    @MainActor
    func nestedEditReachesBothSets() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let nestedSibling = try pair.source.duplicateAsClone(pair.member.nested)
        pair.graph.syncCloneSets()

        let nested = try #require(pair.current(pair.member.nested))
        let nestedInner = try #require(pair.current(pair.member.nestedInner))
        nestedInner.offset = CGSize(width: 99, height: 99)
        pair.graph.syncCloneSets(editedIn: nested.subGraph)

        let currentNestedSibling = try #require(pair.current(nestedSibling))
        let nestedSiblingInner = try #require(CloneSetModel.counterpart(of: nestedInner, from: nested, in: currentNestedSibling))
        #expect(nestedSiblingInner.offset == CGSize(width: 99, height: 99))
        #expect(pair.counterpart(of: pair.member.nestedInner)?.offset == CGSize(width: 99, height: 99))
    }

    @Test("Edits outside any clone set sync nothing, and an unlinked member's edits reach no one")
    @MainActor
    func editsOutsideSetsSyncNothing() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let before = try snapshot(pair.member.member)

        pair.graph.addNode(NumberBinaryOperator(context: context))
        pair.graph.syncCloneSets()
        #expect(try snapshot(pair.member.member) == before)

        try pair.graph.unlinkClone(pair.sibling)
        pair.target.addNode(NumberBinaryOperator(context: context))
        pair.graph.syncCloneSets()
        #expect(pair.source.nodes.count == 3)
    }

    @Test("A settings change made in the settings view reaches the sibling, and undo takes it back from both")
    @MainActor
    func settingsChangeWithoutPortChangeSyncs() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let expression = MathExpressionNode(context: context, expression: "sin(x) + y")
        pair.edit { pair.source.addNode(expression) }
        #expect(pair.counterpart(of: expression)?.stringExpression == "sin(x) + y")

        let session = NodeSettingsSession(node: expression)
        expression.stringExpression = "cos(x) + y"
        // Closing the view records the step, its group's close syncing it.
        session.end()
        #expect(pair.counterpart(of: expression)?.stringExpression == "cos(x) + y")

        pair.undoManager.undo()
        #expect(pair.current(expression)?.stringExpression == "sin(x) + y")
        #expect(pair.counterpart(of: expression)?.stringExpression == "sin(x) + y")

        pair.undoManager.redo()
        #expect(pair.counterpart(of: expression)?.stringExpression == "cos(x) + y")
    }

    @Test("Unlinking a member nested inside a member reaches the siblings")
    @MainActor
    func nestedMembershipChangeSyncs() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let nestedSibling = try pair.source.duplicateAsClone(pair.member.nested)
        pair.graph.syncCloneSets()
        #expect(pair.counterpart(of: pair.member.nested)?.cloneSetID != nil)

        try pair.source.unlinkClone(try #require(pair.current(pair.member.nested)))
        pair.graph.syncCloneSets()

        #expect(pair.counterpart(of: pair.member.nested)?.cloneSetID == nil)
        #expect(pair.counterpart(of: nestedSibling)?.cloneSetID != nil)
    }

    @Test("An edit made before its member leaves the set stays with the siblings, and both undo in turn")
    @MainActor
    func unlinkAfterAnEdit() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.edit { pair.source.addNode(NumberBinaryOperator(context: context)) }
        try pair.edit { try pair.graph.unlinkClone(pair.member.member) }
        #expect(pair.target.nodes.count == 4)
        #expect(pair.member.member.cloneSetID == nil)

        pair.undoManager.undo()
        #expect(pair.member.member.cloneSetID != nil)
        pair.undoManager.undo()
        #expect(pair.source.nodes.count == 3)
        #expect(pair.target.nodes.count == 3)
    }

    @Test("An edit made in one member reaches the copy Duplicate as Clone then makes of another")
    @MainActor
    func duplicateAfterAnEdit() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.edit { pair.target.addNode(NumberBinaryOperator(context: context)) }      // an edit in B
        let third = try pair.edit { try pair.graph.duplicateAsClone(pair.member.member) }   // copied from A

        #expect(pair.source.nodes.count == 4)
        #expect(third.subGraph.nodes.count == 4)
    }
}

// MARK: - Background save

extension CloneSetContractTests
{
    @Test("A save on a background queue writes the members as they are, and syncs nothing")
    func backgroundSaveSyncsNothing() async throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)
        let edited = try await MainActor.run {
            // An edit that registers no undo, so no undo group syncs it.
            let node = NumberBinaryOperator(context: context)
            pair.graph.withoutUndoRegistration { pair.source.addNode(node) }
            return (node.id, try snapshot(pair.sibling))
        }

        // FileDocument.fileWrapper(configuration:) runs off the main thread.
        let data = try await Task.detached {
            try JSONEncoder().encode(pair.graph)
        }.value

        #expect(try snapshot(pair.sibling) == edited.1)
        let decoded = try decode(data, context: context)
        let decodedSource = try #require(decoded.cloneSetMembers(of: setID).first { $0.id == pair.member.member.id })
        #expect(decodedSource.subGraph.node(forID: edited.0) != nil)
    }
}

// MARK: - Storage

extension CloneSetContractTests
{
    @Test("A saved document holds each member whole, its own values with it, and loads it back")
    @MainActor
    func membersSaveAndLoad() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)
        _ = try pair.source.duplicateAsClone(pair.member.nested)   // a nested set inside the member
        pair.graph.syncCloneSets()
        let nestedSetID = try #require(pair.member.nested.cloneSetID)

        // A parent wire onto the sibling's published inlet, and a per-member value on it.
        let upstream = NumberBinaryOperator(context: context)
        pair.graph.addNode(upstream)
        let siblingProxy = try #require(pair.sibling.ports.first { $0.kind == .Inlet && $0.displayName == "Amount" })
        _ = try #require(pair.graph.connect(upstream.outputNumber, to: siblingProxy))
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        try #require(pair.current(pair.member.first)).inputNumber1.value = 1
        firstCopy.inputNumber1.value = 5

        let data = try save(pair.graph)
        #expect(try memberEntries(in: data).count == 2)

        let decoded = try decode(data, context: context)
        #expect(decoded.missingNodeDiagnostics.isEmpty)
        let members = decoded.cloneSetMembers(of: setID)
        #expect(members.map(\.id) == [pair.member.member.id, pair.sibling.id])
        // Every id is the one the document knew.
        #expect(Set(members[0].subGraph.nodesRecursive().map(\.id)) == Set(pair.source.nodesRecursive().map(\.id)))
        #expect(Set(members[1].subGraph.nodesRecursive().map(\.id)) == Set(pair.target.nodesRecursive().map(\.id)))
        #expect(node(withID: firstCopy.id, in: members[1], as: NumberBinaryOperator.self)?.inputNumber1.value == 5)
        #expect(node(withID: pair.member.first.id, in: members[0], as: NumberBinaryOperator.self)?.inputNumber1.value == 1)
        // The parent's wire onto the sibling's proxy survived.
        let decodedUpstream = try #require(decoded.node(forID: upstream.id) as? NumberBinaryOperator)
        let decodedProxy = try #require(members[1].ports.first { $0.id == siblingProxy.id })
        #expect(decoded.connections.contains { $0.outletPort === decodedUpstream.outputNumber && $0.inletPort === decodedProxy })
        // The nested set came back too.
        #expect(decoded.cloneSets.count == 2)
        #expect(decoded.cloneSetMembers(of: nestedSetID).count == 4)
    }

    @Test("A loaded member is in step with its set: a sync from its sibling changes nothing")
    @MainActor
    func loadedMembersAreInStep() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)
        _ = try pair.source.duplicateAsClone(pair.member.nested)
        try #require(pair.current(pair.member.first)).inputNumber1.value = 2
        try #require(pair.counterpart(of: pair.member.first)).inputNumber1.value = 6

        let decoded = try decode(try save(pair.graph), context: context)
        let members = decoded.cloneSetMembers(of: setID)
        try #require(members.count == 2)

        let loaded = try snapshot(members[1])
        CloneSetModel.syncSiblings(of: members[0])
        #expect(try snapshot(members[1]) == loaded)
    }

    @Test("A save from another queue writes the members and keeps their values")
    func backgroundSaveKeepsValues() async throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)

        await MainActor.run { pair.graph.syncCloneSets() }
        let firstCopyID: UUID = try await MainActor.run {
            let copy = try #require(pair.counterpart(of: pair.member.first))
            try #require(pair.current(pair.member.first)).inputNumber1.value = 2
            copy.inputNumber1.value = 7
            return copy.id
        }

        // FileDocument.fileWrapper(configuration:) runs off the main thread.
        let data = try await Task.detached { try save(pair.graph) }.value

        #expect(try memberEntries(in: data).count == 2)

        // Held, not a temporary: a graph released tears down its nodes' ports.
        let decoded = try decode(data, context: context)
        let members = decoded.cloneSetMembers(of: setID)
        try #require(members.count == 2)
        let decodedCopy = try #require(node(withID: firstCopyID, in: members[1], as: NumberBinaryOperator.self))
        let decodedFirst = try #require(node(withID: pair.member.first.id, in: members[0], as: NumberBinaryOperator.self))
        #expect(decodedCopy.inputNumber1.value == 7)
        #expect(decodedFirst.inputNumber1.value == 2)
    }

    @Test("A member exposing a nested sub graph's knob saves and loads, each member's value its own")
    @MainActor
    func nestedPublishedProxySurvivesASave() throws
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

        let siblingNestedInner = try #require(pair.counterpart(of: pair.member.nestedInner))
        try #require(pair.current(pair.member.nestedInner)).inputNumber1.value = 3
        siblingNestedInner.inputNumber1.value = 9

        let decoded = try decode(try save(pair.graph), context: context)

        #expect(decoded.missingNodeDiagnostics.isEmpty)
        let members = decoded.cloneSetMembers(of: setID)
        try #require(members.count == 2)
        #expect(node(withID: pair.member.nestedInner.id, in: members[0], as: NumberBinaryOperator.self)?.inputNumber1.value == 3)
        #expect(node(withID: siblingNestedInner.id, in: members[1], as: NumberBinaryOperator.self)?.inputNumber1.value == 9)
    }

    @Test("A knob a plain nested sub graph publishes but the member does not is design, and reaches the siblings")
    @MainActor
    func nestedKnobNotPublishedOnIsDesign() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let nested = try #require(pair.current(pair.member.nested))
        let nestedInner = try #require(pair.current(pair.member.nestedInner))
        nestedInner.inputNumber1.published = true
        nested.subGraph.rebuildPublishedParameterGroup()
        pair.graph.syncCloneSets(editedIn: nested.subGraph)

        // Set where the member's own canvas shows it, on the nested node's proxy.
        try #require(proxy(in: nested, over: nestedInner.inputNumber1) as? NodePort<Float>).value = 3
        try #require(pair.current(pair.member.nestedInner)).inputNumber1.value = 3
        pair.graph.syncCloneSets(editedIn: pair.source)

        #expect(pair.counterpart(of: pair.member.nestedInner)?.inputNumber1.value == 3)
    }

    @Test("A save keeps a member's own proxy state and nested per-member values")
    @MainActor
    func saveKeepsProxyStateAndNestedValues() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)
        pair.graph.syncCloneSets()

        // Publish one of the sibling's proxies onward, up into the root graph, and rename it there.
        let siblingProxy = try #require(pair.sibling.ports.first { $0.kind == .Inlet && $0.displayName == "Amount" })
        siblingProxy.published = true
        siblingProxy.publishedName = "Root Amount"
        pair.graph.rebuildPublishedParameterGroup()

        // A published inlet two levels down, published on to the member's
        // edge, so its value is each member's own.
        let nested = try #require(pair.current(pair.member.nested))
        let nestedInner = try #require(pair.current(pair.member.nestedInner))
        nestedInner.inputNumber1.published = true
        nested.subGraph.rebuildPublishedParameterGroup()
        try #require(proxy(in: nested, over: nestedInner.inputNumber1)).published = true
        pair.source.rebuildPublishedParameterGroup()
        pair.graph.syncCloneSets(editedIn: nested.subGraph)
        let nestedInnerCopy = try #require(pair.counterpart(of: pair.member.nestedInner))
        try #require(pair.current(pair.member.nestedInner)).inputNumber1.value = 7
        nestedInnerCopy.inputNumber1.value = 5
        pair.graph.syncCloneSets()

        let data = try save(pair.graph)
        #expect(membersAreInStep(pair))
        let decoded = try decode(data, context: context)

        let decodedSibling = try #require(decoded.cloneSetMembers(of: setID).first { $0.id == pair.sibling.id })
        let decodedProxy = try #require(decodedSibling.ports.first { $0.id == siblingProxy.id })
        #expect(decodedProxy.published)
        #expect(decodedProxy.publishedName == "Root Amount")
        #expect(decoded.publishedInputPorts().contains { $0.id == siblingProxy.id })

        #expect(node(withID: nestedInnerCopy.id, in: decodedSibling, as: NumberBinaryOperator.self)?.inputNumber1.value == 5)
        let decodedMember = try #require(decoded.cloneSetMembers(of: setID).first { $0.id == pair.member.member.id })
        #expect(node(withID: pair.member.nestedInner.id, in: decodedMember, as: NumberBinaryOperator.self)?.inputNumber1.value == 7)
    }

    @Test("A member whose design has drifted from its set keeps its drift through a save")
    @MainActor
    func driftedMemberKeepsItsDrift() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        pair.graph.syncCloneSets()

        // An edit the set has not seen: made, and not yet synced.
        let added = NumberBinaryOperator(context: context)
        pair.target.addNode(added)

        let decoded = try decode(try JSONEncoder().encode(pair.graph), context: context)
        let decodedSibling = try #require(decoded.node(forID: pair.sibling.id) as? SubgraphNode)
        #expect(decodedSibling.subGraph.nodes.count == 4)
        #expect(decodedSibling.subGraph.node(forID: added.id) != nil)
        let decodedMember = try #require(decoded.node(forID: pair.member.member.id) as? SubgraphNode)
        #expect(decodedMember.subGraph.nodes.count == 3)
    }

    @Test("A value set by hand on an inlet whose only wire is switched off is design, and reaches the siblings")
    @MainActor
    func valueBehindASwitchedOffWireIsDesign() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let wire = try #require(pair.source.connections.first)

        pair.edit { _ = pair.source.setConnection(wire, active: false) }
        pair.member.second.inputNumber1.value = 0.5
        pair.graph.syncCloneSets(editedIn: pair.source)

        #expect(pair.counterpart(of: pair.member.second)?.inputNumber1.value == 0.5)
        pair.graph.syncCloneSets()
        #expect(membersAreInStep(pair))
    }

    @Test("The design rule finds a member's own and driven inlets in its encoding, so a change to how ports encode fails here")
    @MainActor
    func designRuleReadsTheEncoding() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        // A knob two levels down, published on to the member's edge.
        fixture.nestedInner.inputNumber1.published = true
        fixture.nested.subGraph.rebuildPublishedParameterGroup()
        try #require(proxy(in: fixture.nested, over: fixture.nestedInner.inputNumber1)).published = true
        fixture.member.subGraph.rebuildPublishedParameterGroup()

        let object = try #require(CloneSet.jsonObject(from: try JSONEncoder().encode(fixture.member.subGraph)))
        let inlets = Graph.nonDesignInlets(inGraph: object).inlets
        #expect(inlets[fixture.first.inputNumber1.id.uuidString] == .memberOwn)
        #expect(inlets[fixture.second.inputNumber1.id.uuidString] == .driven)
        #expect(inlets[fixture.nested.id.uuidString + "/" + fixture.nestedInner.inputNumber1.id.uuidString] == .memberOwn)
        #expect(inlets.count == 3)
        #expect(Set(fixture.member.subGraph.memberOwnInlets().values.map(\.id))
            == [fixture.first.inputNumber1.id, fixture.nestedInner.inputNumber1.id])
    }

    @Test("Values arriving over wires inside a member are not design, so members whose wired values differ stay in step")
    @MainActor
    func wiredValuesKeepMembersInStep() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        pair.graph.syncCloneSets()

        // second.inputNumber1 is wired from first; each member's has arrived at its own value.
        try #require(pair.current(pair.member.second)).inputNumber1.value = 1
        try #require(pair.counterpart(of: pair.member.second)).inputNumber1.value = 2

        pair.graph.syncCloneSets()
        #expect(membersAreInStep(pair))
    }

}

// MARK: - Fidelity

extension CloneSetContractTests
{
    /// Node types that need a device, a permission, a download or a file to
    /// construct; the encode/decode contract they rely on is the same.
    private static let liveSourceNamePattern = #"Camera|Audio|Screen|Syphon|Model|Movie|Video|Hand|Face|Pose|Vision|MIDI|OSC|Capture|Microphone|Speech|Image Loader|Loader|Recorder|Writer|Export"#

    @Test("Every core node type clones as itself, and the clone is in step with its source")
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
            guard let copy = CloneSetModel.counterpart(of: node, from: member, in: sibling) else
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

        let cloned = try snapshot(sibling)
        CloneSetModel.syncSiblings(of: member)
        #expect(try snapshot(sibling) == cloned)
    }
}

// MARK: - Divergences

extension CloneSetContractTests
{
    @Test("A sync leaves the sibling's untouched nodes in place, and what they hold at runtime with them")
    func siblingNodesSurviveSync() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let untouched = try #require(pair.counterpart(of: pair.member.second))

        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.sync()

        expecting(.siblingNodesAreReplaced) {
            #expect(pair.counterpart(of: pair.member.second) === untouched)
        }
    }

    @Test("An edit made in a sibling can still be undone after another member's edit has synced into it")
    @MainActor
    func siblingUndoSurvivesSync() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.edit { pair.target.addNode(NumberBinaryOperator(context: context)) }   // an edit in B
        pair.edit { pair.source.addNode(NumberBinaryOperator(context: context)) }   // then one in A
        #expect(pair.target.nodes.count == 5)

        pair.undoManager.undo()                                                      // A's edit
        #expect(pair.source.nodes.count == 4)
        #expect(pair.target.nodes.count == 4)

        #expect(pair.undoManager.canUndo)
        pair.undoManager.undo()                                                  // B's edit
        #expect(pair.source.nodes.count == 3)
        #expect(pair.target.nodes.count == 3)
    }

    @Test("A value set through its control in a sibling can still be undone after another member's edit has synced into it")
    @MainActor
    func siblingValueUndoSurvivesSync() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let secondInB = try #require(pair.counterpart(of: pair.member.second))
        let parameter = try #require(secondInB.inputNumber2.parameter as? FloatParameter)
        let control = ParameterObservableModel(label: parameter.label,
                                               get: { parameter.value },
                                               set: { parameter.value = $0 },
                                               publisher: parameter.valuePublisher,
                                               graph: pair.target,
                                               undoTarget: parameter)
        let before = secondInB.inputNumber2.value

        pair.edit { control.uiValue = 0.7 }                                            // in B
        pair.edit { pair.source.addNode(NumberBinaryOperator(context: context)) }     // then in A
        #expect(pair.current(pair.member.second)?.inputNumber2.value == 0.7)

        pair.undoManager.undo()                                                        // A's edit
        pair.undoManager.undo()                                                        // B's value
        #expect(pair.counterpart(of: pair.member.second)?.inputNumber2.value == before)
        #expect(pair.current(pair.member.second)?.inputNumber2.value == before)
    }

    @Test("An edit in a sibling can still be undone after a deletion that synced into it is undone")
    @MainActor
    func siblingUndoSurvivesADeletionUndone() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let originalIDs = Set(pair.source.nodes.map(\.id))

        pair.edit { pair.target.addNode(NumberBinaryOperator(context: context)) }          // added in B
        let addedInA = try #require(pair.source.nodes.first { !originalIDs.contains($0.id) })
        pair.edit { pair.source.delete(node: addedInA) }                                   // deleted in A
        #expect(pair.target.nodes.count == 3)

        pair.undoManager.undo()                                                            // the deletion
        #expect(pair.source.nodes.count == 4)
        #expect(pair.target.nodes.count == 4)

        pair.undoManager.undo()                                                        // B's addition
        #expect(pair.target.nodes.count == 3)
        #expect(pair.source.nodes.count == 3)
    }
}

// MARK: - Review findings

/// Behaviour the bake-off review found at risk, on one model or both.
extension CloneSetContractTests
{
    @Test("Unpublishing in one member takes the parent's wires onto every sibling's proxy for it")
    @MainActor
    func syncedUnpublishTakesSiblingParentWires() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let upstream = NumberBinaryOperator(context: context)
        pair.graph.addNode(upstream)
        let siblingProxy = try #require(pair.sibling.ports.first { $0.kind == .Inlet && $0.displayName == "Amount" })
        _ = try #require(pair.graph.connect(upstream.outputNumber, to: siblingProxy))

        pair.source.setPublished(false, on: pair.member.first.inputNumber1)
        pair.sync()

        #expect(!pair.sibling.ports.contains { $0.kind == .Inlet && $0.displayName == "Amount" })
        #expect(pair.graph.connections.isEmpty)
        #expect(upstream.outputNumber.connections.isEmpty)

        // Publishing again brings back a proxy no stale wire is bound to.
        pair.source.setPublished(true, on: pair.member.first.inputNumber1)
        pair.sync()
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        let republished = try #require(proxy(in: pair.sibling, over: firstCopy.inputNumber1))
        #expect(republished.connections.isEmpty)
    }

    @Test("A node rebuilt by a settings change keeps the sibling's own values and proxy state")
    func rebuiltNodeKeepsSiblingState() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let expression = MathExpressionNode(context: context, expression: "x + y")
        pair.source.addNode(expression)
        let inletX = try #require(expression.findPort(named: "x", as: Fabric.Port.self))
        pair.source.setPublished(true, on: inletX)
        pair.sync()

        // The sibling's own value, and its parent's rename and onward publish of the proxy.
        let siblingExpression = try #require(pair.counterpart(of: expression))
        let siblingX = try #require(siblingExpression.findPort(named: "x", as: Fabric.Port.self) as? NodePort<Float>)
        siblingX.value = 5
        let siblingProxy = try #require(proxy(in: pair.sibling, over: siblingX))
        siblingProxy.publishedName = "Speed"
        siblingProxy.published = true
        pair.graph.rebuildPublishedParameterGroup()

        expression.stringExpression = "x * y"
        pair.sync()

        let rebuilt = try #require(pair.counterpart(of: expression))
        #expect(rebuilt.stringExpression == "x * y")
        let rebuiltX = try #require(rebuilt.findPort(named: "x", as: Fabric.Port.self) as? NodePort<Float>)
        #expect(rebuiltX.value == 5)
        let rebuiltProxy = try #require(proxy(in: pair.sibling, over: rebuiltX))
        #expect(rebuiltProxy.publishedName == "Speed")
        #expect(rebuiltProxy.published)
        #expect(pair.graph.publishedInputPorts().contains { $0 === rebuiltProxy })
    }

    @Test("Two instances of a nested set inside one member keep their own values through the outer sync and a save")
    @MainActor
    func nestedInstancesInOneMemberKeepTheirValues() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)
        pair.member.nestedInner.inputNumber1.published = true
        pair.member.nested.subGraph.rebuildPublishedParameterGroup()
        let nestedSibling = try pair.source.duplicateAsClone(pair.member.nested)
        pair.graph.syncCloneSets()

        // Both nested instances inside the outer sibling, each with a value of its own.
        let siblingNested = try #require(pair.counterpart(of: pair.member.nested))
        let siblingNestedSibling = try #require(pair.counterpart(of: nestedSibling))
        let innerOne = try #require(CloneSetModel.counterpart(of: pair.member.nestedInner, from: pair.member.nested, in: siblingNested))
        let innerTwo = try #require(CloneSetModel.counterpart(of: pair.member.nestedInner, from: pair.member.nested, in: siblingNestedSibling))
        innerOne.inputNumber1.value = 4
        innerTwo.inputNumber1.value = 5

        try #require(pair.current(pair.member.second)).inputNumber2.value = 1   // an outer edit in the source
        pair.graph.syncCloneSets()

        func values(in outer: SubgraphNode) -> [Float?]
        {
            outer.subGraph.nodes.compactMap { $0 as? SubgraphNode }
                .compactMap { $0.subGraph.nodes.first as? NumberBinaryOperator }
                .map(\.inputNumber1.value)
        }
        #expect(values(in: pair.sibling) == [4, 5])

        let decoded = try decode(try save(pair.graph), context: context)
        let decodedSibling = try #require(decoded.cloneSetMembers(of: setID).last)
        #expect(values(in: decodedSibling) == [4, 5])
    }

    @Test("Publishing inside a nested set leaves the outer members in step")
    @MainActor
    func nestedPublishKeepsOuterMembersInStep() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        _ = try pair.source.duplicateAsClone(pair.member.nested)
        pair.graph.syncCloneSets()

        let nested = try #require(pair.current(pair.member.nested))
        let nestedInner = try #require(pair.current(pair.member.nestedInner))
        nested.subGraph.setPublished(true, on: nestedInner.inputNumber2)
        pair.graph.syncCloneSets()

        pair.graph.syncCloneSets()
        #expect(membersAreInStep(pair))
    }

    @Test("Opening a document is not an edit: its members are left as they were saved")
    func openingSyncsNothing() async throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)
        pair.target.addNode(NumberBinaryOperator(context: context))      // drift, saved in full
        let data = try JSONEncoder().encode(pair.graph)

        // Documents decode off the main thread.
        let decoded = try await Task.detached { try decode(data, context: context) }.value
        try await Task.sleep(for: .milliseconds(50))

        let counts = await MainActor.run { decoded.cloneSetMembers(of: setID).map(\.subGraph.nodes.count) }
        #expect(counts == [3, 4])
    }

    @Test("A document with one unreadable clone set still opens, with its other sets")
    func unreadableSetDoesNotBlockOpening() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)
        var object = try #require(JSONSerialization.jsonObject(with: try JSONEncoder().encode(pair.graph)) as? [String: Any])
        var sets = try #require(object["cloneSets"] as? [Any])
        sets.append(["unreadable": true])
        object["cloneSets"] = sets

        let decoded = try decode(try JSONSerialization.data(withJSONObject: object), context: context)

        #expect(decoded.cloneSet(for: setID) != nil)
        #expect(decoded.cloneSetMembers(of: setID).count == 2)
    }

    @Test("A new document location rewrites the set's design with its members, so they stay in step")
    @MainActor
    func fileReferenceRewriteKeepsMembersInStep() throws
    {
        guard let context = makeContext() else { return }
        let oldDirectory = URL(filePath: "/tmp/Project", directoryHint: .isDirectory)
        let pair = try makePair(context: context)
        pair.graph.updateFileReferenceBaseURL(oldDirectory)
        let loader = TextFileLoaderNode(context: context)
        loader.setFileURL(oldDirectory.appending(path: "Assets/source.txt"))
        pair.edit { pair.source.addNode(loader) }
        pair.graph.rewriteFileReferences(relativeTo: oldDirectory)

        pair.graph.rewriteFileReferences(relativeTo: oldDirectory.appending(path: "Versions", directoryHint: .isDirectory))
        #expect(pair.counterpart(of: loader)?.inputFilePathParam.value == "../Assets/source.txt")
        pair.graph.syncCloneSets()
        #expect(membersAreInStep(pair))
    }

    @Test("A set that cannot be read is written back as it was saved, and its members open whole")
    @MainActor
    func unreadableSetIsKeptAndItsMembersOpen() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        firstCopy.inputNumber1.value = 5

        // The set's entry loses a key it cannot be read without.
        var object = try #require(JSONSerialization.jsonObject(with: try save(pair.graph)) as? [String: Any])
        var sets = try #require(object["cloneSets"] as? [[String: Any]])
        let name = try #require(sets[0]["name"])
        sets[0]["name"] = nil
        object["cloneSets"] = sets

        let opened = try decode(try JSONSerialization.data(withJSONObject: object), context: context)
        let openedSibling = try #require(opened.node(forID: pair.sibling.id) as? SubgraphNode)
        #expect(openedSibling.subGraph.nodes.count == 3)
        #expect(node(withID: firstCopy.id, in: openedSibling, as: NumberBinaryOperator.self)?.inputNumber1.value == 5)

        // Saved again, the set is as it was; repaired, it reads.
        var resaved = try #require(JSONSerialization.jsonObject(with: try JSONEncoder().encode(opened)) as? [String: Any])
        var resavedSets = try #require(resaved["cloneSets"] as? [[String: Any]])
        #expect(resavedSets.count == 1)
        resavedSets[0]["name"] = name
        resaved["cloneSets"] = resavedSets

        let repaired = try decode(try JSONSerialization.data(withJSONObject: resaved), context: context)
        #expect(repaired.cloneSet(for: setID) != nil)
        #expect(repaired.cloneSetMembers(of: setID).count == 2)
    }

    @Test("A member brought back by undo is in step with its set, the edits made while it was gone undone first")
    @MainActor
    func restoredMemberIsInStep() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)
        pair.edit { pair.graph.delete(node: pair.sibling) }
        pair.edit { pair.source.setPublished(true, on: pair.member.second.outputNumber) }

        pair.undoManager.undo()
        pair.undoManager.undo()
        #expect(pair.graph.cloneSetMembers(of: setID).count == 2)
        #expect(membersAreInStep(pair))
        #expect(pair.counterpart(of: pair.member.second)?.outputNumber.published == false)

        // An edit in the restored sibling reaches the member and takes nothing back.
        pair.edit { try? #require(pair.counterpart(of: pair.member.first)).offset = CGSize(width: 30, height: 30) }
        pair.graph.syncCloneSets(editedIn: pair.target)
        #expect(pair.current(pair.member.first)?.offset == CGSize(width: 30, height: 30))
        #expect(pair.current(pair.member.second)?.outputNumber.published == false)
    }

    @Test("An edit in a member and the member's deletion, undone in turn, leave the members in step")
    @MainActor
    func deletedMemberTakesNoPendingEditWithIt() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let inner = try #require(pair.counterpart(of: pair.member.second))

        pair.edit { pair.target.setPublished(true, on: inner.outputNumber) }
        #expect(pair.current(pair.member.second)?.outputNumber.published == true)
        pair.edit { pair.graph.delete(node: pair.sibling) }

        pair.undoManager.undo()
        #expect(membersAreInStep(pair))
        #expect(pair.counterpart(of: pair.member.second)?.outputNumber.published == true)

        pair.undoManager.undo()
        #expect(membersAreInStep(pair))
        #expect(pair.current(pair.member.second)?.outputNumber.published == false)
        #expect(pair.counterpart(of: pair.member.second)?.outputNumber.published == false)
    }

    @Test("A copy brought back by redo is in step with the member it was copied from")
    @MainActor
    func redoneCopyIsInStep() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        fixture.graph.undoManager = undoManager
        fixture.member.subGraph.undoManager = undoManager

        undoManager.beginUndoGrouping()
        let copy = try fixture.graph.duplicateAsClone(fixture.member)
        undoManager.endUndoGrouping()
        undoManager.beginUndoGrouping()
        fixture.member.subGraph.setPublished(true, on: fixture.second.outputNumber)
        undoManager.endUndoGrouping()

        undoManager.undo()
        undoManager.undo()
        undoManager.redo()
        undoManager.redo()

        let copied = try #require(CloneSetModel.counterpart(of: fixture.second, from: fixture.member, in: copy))
        #expect(copied.outputNumber.published)
        #expect(fixture.second.outputNumber.published)
        #expect(CloneSetModel.isInStep(copy))
    }

    @Test("A canvas standing inside a sibling keeps editing the live sibling after a sync")
    @MainActor
    func canvasInsideSiblingFollowsSync() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let canvas = GraphCanvasContext(rootGraph: pair.graph)
        canvas.enter(pair.sibling)
        if let siblingNested = pair.counterpart(of: pair.member.nested)
        {
            canvas.enter(siblingNested)
        }

        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.graph.syncCloneSets()

        let liveNested = pair.counterpart(of: pair.member.nested)
        #expect(canvas.currentGraph === liveNested?.subGraph)

        // An edit made there now reaches the source.
        canvas.currentGraph.addNode(NumberBinaryOperator(context: context))
        pair.graph.syncCloneSets()
        #expect(pair.current(pair.member.nested)?.subGraph.nodes.count == 2)
    }
}
