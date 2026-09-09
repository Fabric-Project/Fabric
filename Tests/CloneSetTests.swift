import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// Clone sets: Subgraph nodes kept identical in design to a set's template
/// while each executes on its own. A set is a root-level object holding the
/// template as data; each member keeps a record mapping the template's ids to
/// its own. See CloneSet and SubgraphNode.cloneSetID.
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
        let data = try JSONEncoder().encode(graph)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        return try decoder.decode(Graph.self, from: data)
    }

    /// A member with two wired inner nodes, one published inlet and a nested
    /// subgraph, so the record and wiring survive cloning at every level.
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

    /// The node in `member` that stands for `node` of `source`, found through
    /// both members' records: source local id → template id → member local id.
    private func counterpart<T: Node>(of node: T, from source: SubgraphNode, in member: SubgraphNode) -> T?
    {
        guard let templateID = source.templateID(forLocal: node.id),
              let localID = member.localID(forTemplate: templateID)
        else { return nil }
        return member.subGraph.nodesRecursive().first { $0.id == localID } as? T
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

    // MARK: - Sets and records

    @Test("Duplicate as Clone starts a set on the root graph and records both members against its template")
    func duplicateAsCloneStartsASet() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        #expect(fixture.member.cloneSetID == nil)
        #expect(fixture.graph.cloneSets.isEmpty)

        let copy = try #require(fixture.graph.duplicateAsClone(fixture.member))

        let set = try #require(fixture.graph.cloneSets.first)
        #expect(fixture.graph.cloneSets.count == 1)
        #expect(fixture.member.cloneSetID == set.id)
        #expect(copy.cloneSetID == set.id)
        #expect(set.name == "Set A")
        #expect(fixture.graph.cloneSet(for: set.id) === set)

        // Every local id of the source is recorded against a template id, and
        // the copy records the same template ids against its own fresh ids.
        for node in fixture.member.subGraph.nodesRecursive()
        {
            let templateID = try #require(fixture.member.templateID(forLocal: node.id), "\(node)")
            let copyLocal = try #require(copy.localID(forTemplate: templateID))
            #expect(copyLocal != node.id)
            for port in node.ports
            {
                let portTemplateID = try #require(fixture.member.templateID(forLocal: port.id))
                #expect(copy.localID(forTemplate: portTemplateID) != nil)
            }
        }
        #expect(Set(copy.subGraph.nodesRecursive().map(\.id)).isDisjoint(with: fixture.member.subGraph.nodesRecursive().map(\.id)))

        let copiedFirst = try #require(counterpart(of: fixture.first, from: fixture.member, in: copy))
        let copiedSecond = try #require(counterpart(of: fixture.second, from: fixture.member, in: copy))
        let copiedNested = try #require(counterpart(of: fixture.nested, from: fixture.member, in: copy))
        let copiedNestedInner = try #require(counterpart(of: fixture.nestedInner, from: fixture.member, in: copy))
        #expect(copiedFirst.inputNumber1.published)
        #expect(copiedFirst.inputNumber1.publishedName == "Amount")
        #expect(copy.subGraph.connections.count == 1)
        #expect(copy.subGraph.connections.first?.outletPort === copiedFirst.outputNumber)
        #expect(copy.subGraph.connections.first?.inletPort === copiedSecond.inputNumber1)
        #expect(copy.ports.contains { $0.id == copiedFirst.inputNumber1.id && $0 is any ProxyPortProtocol })
        #expect(copiedNestedInner.graph === copiedNested.subGraph)
    }

    @Test("Sets, records and names survive a save")
    func setsRoundTrip() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let copy = try #require(fixture.graph.duplicateAsClone(fixture.member))
        let setID = try #require(fixture.member.cloneSetID)
        fixture.graph.renameCloneSet(setID, to: "Lyric Panel")

        let decoded = try roundTrip(fixture.graph, context: context)

        let decodedSet = try #require(decoded.cloneSet(for: setID))
        #expect(decodedSet.name == "Lyric Panel")
        let members = decoded.cloneSetMembers(of: setID)
        #expect(members.map(\.id) == [fixture.member.id, copy.id])
        #expect(members[0].cloneRecord == fixture.member.cloneRecord)
        #expect(members[1].cloneRecord == copy.cloneRecord)
        #expect(!decodedSet.templateJSON.isEmpty)
        let original = try #require(fixture.graph.cloneSet(for: setID))
        #expect(NSDictionary(dictionary: decodedSet.templateObject) == NSDictionary(dictionary: original.templateObject))
    }

    @Test("Duplicate as Clone is one undoable step that also undoes set creation")
    func duplicateAsCloneUndoes() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let undoManager = UndoManager()
        fixture.graph.undoManager = undoManager

        let copy = try #require(fixture.graph.duplicateAsClone(fixture.member))
        let setID = try #require(fixture.member.cloneSetID)

        undoManager.undo()
        #expect(fixture.graph.nodes.count == 1)
        #expect(fixture.member.cloneSetID == nil)
        #expect(fixture.member.cloneRecord.isEmpty)
        #expect(fixture.graph.cloneSet(for: setID) == nil)

        undoManager.redo()
        #expect(fixture.graph.nodes.count == 2)
        #expect(fixture.member.cloneSetID == setID)
        #expect(fixture.graph.nodes.contains { $0 === copy })
        #expect(copy.cloneSetID == setID)
        #expect(fixture.graph.cloneSet(for: setID) != nil)
    }

    @Test("A plain duplicate of a member carries no clone links")
    func plainDuplicateLeavesTheSet() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        _ = try #require(fixture.member.subGraph.duplicateAsClone(fixture.nested))
        _ = try #require(fixture.graph.duplicateAsClone(fixture.member))

        let plain = try #require(fixture.graph.duplicateNodes([fixture.member]).first as? SubgraphNode)

        #expect(plain.cloneSetID == nil)
        #expect(plain.cloneRecord.isEmpty)
        #expect(plain.subGraph.subgraphNodesRecursive().allSatisfy { $0.cloneSetID == nil && $0.cloneRecord.isEmpty })
    }

    @Test("Members are found across nesting levels, in document order")
    func membersAreDiscoveredAcrossNesting() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let sibling = try #require(fixture.graph.duplicateAsClone(fixture.member))
        let setID = try #require(fixture.member.cloneSetID)

        let container = SubgraphNode(context: context)
        fixture.graph.addNode(container)
        let deepCopy = try #require(fixture.graph.duplicateAsClone(fixture.member))
        fixture.graph.delete(node: deepCopy)
        container.subGraph.addNode(deepCopy)

        let members = fixture.graph.cloneSetMembers(of: setID)
        #expect(members.map(\.id) == [fixture.member.id, sibling.id, deepCopy.id])
        #expect(container.subGraph.cloneSetMembers(of: setID).map(\.id) == members.map(\.id))
        #expect(fixture.graph.cloneSiblings(of: sibling).map(\.id) == [fixture.member.id, deepCopy.id])
        #expect(fixture.graph.cloneSiblings(of: container).isEmpty)
    }

    @Test("Unlink leaves the set and gives nested sets their own copied templates, undoably")
    func unlinkDetaches() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)

        let nestedCopy = try #require(fixture.member.subGraph.duplicateAsClone(fixture.nested))
        let nestedSetID = try #require(fixture.nested.cloneSetID)
        let sibling = try #require(fixture.graph.duplicateAsClone(fixture.member))
        let setID = try #require(fixture.member.cloneSetID)
        #expect(fixture.graph.cloneSetMembers(of: nestedSetID).count == 4)
        #expect(fixture.graph.cloneSets.count == 2)

        let undoManager = UndoManager()
        fixture.graph.undoManager = undoManager
        fixture.graph.unlinkClone(sibling)

        #expect(sibling.cloneSetID == nil)
        #expect(sibling.cloneRecord.isEmpty)
        #expect(fixture.member.cloneSetID == setID)
        #expect(fixture.graph.cloneSetMembers(of: setID).map(\.id) == [fixture.member.id])

        // The unlinked member's nested members form their own set, on a copy of
        // the nested template, so their records still resolve.
        let detached = sibling.subGraph.nodes.compactMap { $0 as? SubgraphNode }
        #expect(detached.count == 2)
        let detachedSetID = try #require(detached.first?.cloneSetID)
        #expect(detachedSetID != nestedSetID)
        #expect(detached.allSatisfy { $0.cloneSetID == detachedSetID })
        let detachedSet = try #require(fixture.graph.cloneSet(for: detachedSetID))
        #expect(detachedSet.name == "Set C")
        #expect(detachedSet.templateJSON == fixture.graph.cloneSet(for: nestedSetID)?.templateJSON)
        #expect(fixture.graph.cloneSetMembers(of: nestedSetID).map(\.id) == [fixture.nested.id, nestedCopy.id])
        for node in detached[0].subGraph.nodes
        {
            #expect(detached[0].templateID(forLocal: node.id) != nil)
        }

        undoManager.undo()
        #expect(sibling.cloneSetID == setID)
        #expect(!sibling.cloneRecord.isEmpty)
        #expect(detached.allSatisfy { $0.cloneSetID == nestedSetID })
        #expect(fixture.graph.cloneSet(for: detachedSetID) == nil)

        undoManager.redo()
        #expect(sibling.cloneSetID == nil)
        #expect(detached.allSatisfy { $0.cloneSetID == detachedSetID })
    }

    @Test("A set with no members left is dropped on save")
    func emptySetsArePrunedOnSave() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let copy = try #require(fixture.graph.duplicateAsClone(fixture.member))
        let setID = try #require(fixture.member.cloneSetID)

        fixture.graph.unlinkClone(copy)
        fixture.graph.unlinkClone(fixture.member)
        #expect(fixture.graph.cloneSet(for: setID) != nil)

        let decoded = try roundTrip(fixture.graph, context: context)
        #expect(decoded.cloneSets.isEmpty)
    }

    // MARK: - Names

    @Test("Sets are named in sequence and renamed on the set, undoably; an empty name restores a system name")
    func namesAndRename() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let sibling = try #require(fixture.graph.duplicateAsClone(fixture.member))
        let setID = try #require(fixture.member.cloneSetID)
        #expect(fixture.graph.cloneSet(for: setID)?.name == "Set A")

        let other = SubgraphNode(context: context)
        fixture.graph.addNode(other)
        _ = try #require(fixture.graph.duplicateAsClone(other))
        let otherSetID = try #require(other.cloneSetID)
        #expect(fixture.graph.cloneSet(for: otherSetID)?.name == "Set B")

        _ = try #require(fixture.member.subGraph.duplicateAsClone(fixture.nested))
        #expect(fixture.graph.cloneSet(for: fixture.nested.cloneSetID!)?.name == "Set C")

        let undoManager = UndoManager()
        fixture.graph.undoManager = undoManager
        fixture.graph.renameCloneSet(setID, to: "  Lyric Panel ")
        #expect(fixture.graph.cloneSet(for: setID)?.name == "Lyric Panel")
        #expect(sibling.subtitle == "Lyric Panel")

        undoManager.undo()
        #expect(sibling.subtitle == "Set A")
        undoManager.redo()
        #expect(sibling.subtitle == "Lyric Panel")

        // Empty goes back to the lowest free system name; A is free again.
        fixture.graph.renameCloneSet(setID, to: "   ")
        #expect(sibling.subtitle == "Set A")
    }

    @Test("Members show the set name as their subtitle and the clone glyph as their title icon")
    func subtitleAndTitleIcon() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        #expect(fixture.member.subtitle == nil)
        #expect(fixture.member.titleIcon == nil)

        let sibling = try #require(fixture.graph.duplicateAsClone(fixture.member))
        let setID = try #require(fixture.member.cloneSetID)
        #expect(fixture.member.subtitle == "Set A")
        #expect(fixture.member.cloneSetInfo == CloneSetInfo(setID: setID, name: "Set A", memberCount: 2))
        let icon = try #require(sibling.titleIcon)
        #expect(icon.systemName == CloneSetInfo.symbolName)
        #expect(icon.tint == .neutral)
        #expect(icon.tooltip == "Clone set: Set A, 2 members. Edits here reach every member.")

        fixture.graph.delete(node: sibling)
        #expect(fixture.member.titleIcon?.tooltip == "Clone set: Set A, 1 member. Edits here reach every member.")
    }

    @Test("The view model mirrors the clone glyph as membership changes")
    @MainActor
    func viewModelMirrorsTitleIcon() async throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let viewModel = fixture.graph.viewModel(for: fixture.member)
        #expect(viewModel.titleIcon == nil)

        let sibling = try #require(fixture.graph.duplicateAsClone(fixture.member))
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.titleIcon?.tooltip.contains("2 members") == true)
        #expect(viewModel.subtitle == "Set A")

        fixture.member.userName = "Left"
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.subtitle == "Left")
        #expect(viewModel.titleIcon?.tooltip.contains("Set A") == true)

        fixture.graph.delete(node: sibling)
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.titleIcon?.tooltip.contains("1 member.") == true)
    }
}
