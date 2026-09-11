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
        try decode(JSONEncoder().encode(graph), context: context)
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

        let copy = try fixture.graph.duplicateAsClone(fixture.member)

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
        let copy = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)
        try fixture.graph.renameCloneSet(setID, to: "Lyric Panel")

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

        let copy = try fixture.graph.duplicateAsClone(fixture.member)
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
        _ = try fixture.member.subGraph.duplicateAsClone(fixture.nested)
        _ = try fixture.graph.duplicateAsClone(fixture.member)

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

    @Test("Unlink leaves the set and gives nested sets their own copied templates, undoably")
    func unlinkDetaches() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)

        let nestedCopy = try fixture.member.subGraph.duplicateAsClone(fixture.nested)
        let nestedSetID = try #require(fixture.nested.cloneSetID)
        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)
        #expect(fixture.graph.cloneSetMembers(of: nestedSetID).count == 4)
        #expect(fixture.graph.cloneSets.count == 2)

        let undoManager = UndoManager()
        fixture.graph.undoManager = undoManager
        try fixture.graph.unlinkClone(sibling)

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
        let copy = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)

        try fixture.graph.unlinkClone(copy)
        try fixture.graph.unlinkClone(fixture.member)
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

        undoManager.undo()
        #expect(sibling.subtitle == "Set A")
        undoManager.redo()
        #expect(sibling.subtitle == "Lyric Panel")

        // Empty goes back to the lowest free system name; A is free again.
        try fixture.graph.renameCloneSet(setID, to: "   ")
        #expect(sibling.subtitle == "Set A")
    }

    @Test("Members show the set name as their subtitle and report a linked status")
    func subtitleAndLinkedStatus() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        #expect(fixture.member.subtitle == nil)
        #expect(fixture.member.status == nil)

        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        let setID = try #require(fixture.member.cloneSetID)
        #expect(fixture.member.subtitle == "Set A")
        #expect(fixture.member.cloneSetInfo == CloneSetInfo(setID: setID, name: "Set A", memberCount: 2))
        let status = try #require(sibling.status)
        #expect(status == .linked("Clone set Set A, 2 members. Edits here reach every member."))
        #expect(status.description == "Linked: Clone set Set A, 2 members. Edits here reach every member.")
        #expect(NodeStatus.warning("w") > status)

        fixture.graph.delete(node: sibling)
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
}

// MARK: - Reconcile

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
        var target: Graph { sibling.subGraph }

        func sync() { graph.reconcileCloneSiblings(of: member.member) }

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

        /// The sibling's node for one of the source member's, at any depth,
        /// through the two records.
        func counterpart<T: Node>(of node: T) -> T?
        {
            guard let templateID = member.member.templateID(forLocal: node.id),
                  let localID = sibling.localID(forTemplate: templateID)
            else { return nil }
            return sibling.subGraph.nodesRecursive().first { $0.id == localID } as? T
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

    @Test("Adding and wiring a node in one member appears in the sibling, and both records grow")
    func addedNodeAppearsInSibling() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let added = NumberBinaryOperator(context: context)
        added.offset = CGSize(width: 300, height: 40)
        pair.source.addNode(added)
        _ = try #require(pair.source.connect(pair.member.second.outputNumber, to: added.inputNumber2))
        #expect(pair.member.member.templateID(forLocal: added.id) == nil)

        pair.syncExpectingNoUndo()

        let addedCopy = try #require(pair.counterpart(of: added))
        let secondCopy = try #require(pair.counterpart(of: pair.member.second))
        #expect(addedCopy.id != added.id)
        #expect(addedCopy.offset == added.offset)
        #expect(pair.target.nodes.count == 4)
        #expect(pair.target.connections.count == 2)
        #expect(pair.target.connections.contains {
            $0.outletPort === secondCopy.outputNumber && $0.inletPort === addedCopy.inputNumber2
        })
        #expect(pair.member.member.templateID(forLocal: added.inputNumber2.id) != nil)
        let addedInletTemplateID = try #require(pair.member.member.templateID(forLocal: added.inputNumber2.id))
        #expect(pair.sibling.localID(forTemplate: addedInletTemplateID) == addedCopy.inputNumber2.id)
    }

    @Test("Deleting a node in one member removes it and its wires from the sibling")
    func deletedNodeLeavesSibling() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.source.delete(node: pair.member.second)
        pair.sync()

        #expect(pair.counterpart(of: pair.member.second) == nil)
        #expect(pair.target.nodes.count == 2)
        #expect(pair.target.connections.isEmpty)
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

    @Test("Publishing in the source adds a proxy on the sibling's node; unpublishing removes it")
    func publishedPortsFollow() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let secondCopy = try #require(pair.counterpart(of: pair.member.second))
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))

        pair.member.second.outputNumber.published = true
        pair.member.second.outputNumber.publishedName = "Result"
        pair.member.first.inputNumber1.published = false
        pair.source.rebuildPublishedParameterGroup()

        pair.sync()

        #expect(secondCopy.outputNumber.published)
        #expect(secondCopy.outputNumber.publishedName == "Result")
        #expect(firstCopy.inputNumber1.published == false)
        #expect(pair.sibling.ports.contains { $0.id == secondCopy.outputNumber.id && $0 is any ProxyPortProtocol })
        #expect(pair.sibling.ports.contains { $0.id == firstCopy.inputNumber1.id } == false)
    }

    @Test("Published inlet values stay per member; unpublished values follow the source")
    func valuesSplitAtThePublishBoundary() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))
        let secondCopy = try #require(pair.counterpart(of: pair.member.second))

        pair.member.first.inputNumber1.value = 1
        firstCopy.inputNumber1.value = 5
        pair.member.second.inputNumber2.value = 7
        secondCopy.inputNumber2.value = 8
        pair.member.first.inputNumber2.value = 9
        firstCopy.inputNumber2.value = 9

        pair.sync()

        #expect(firstCopy.inputNumber1.value == 5)
        #expect(secondCopy.inputNumber2.value == 7)
        #expect(firstCopy.inputNumber2.value == 9)
        #expect(secondCopy.inputNumber1.connections.count == 1)
    }

    @Test("Layout, renames and notes follow the source")
    func layoutAndRenameFollow() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))

        pair.member.first.offset = CGSize(width: -120, height: 64)
        pair.member.first.userName = "Gain"
        let note = Note(note: "Feed this from the clock", rect: CGRect(x: 1, y: 2, width: 300, height: 100))
        pair.source.addNote(note)

        pair.sync()

        #expect(firstCopy.offset == pair.member.first.offset)
        #expect(firstCopy.userName == "Gain")
        #expect(pair.target.notes.count == 1)
        #expect(pair.target.notes.first?.note == note.note)
        #expect(pair.target.notes.first?.rect == note.rect)
    }

    @Test("A settings change that rebuilds ports replaces the sibling's node, keeping its ids, and rewires it")
    func settingsChangeReplacesNode() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let sampler = SampleAndHoldNode(context: context)
        sampler.strategy = PortType.Float.rawValue
        pair.source.addNode(sampler)
        let inlet = try #require(sampler.findPort(named: "inputValue", as: Port.self))
        _ = try #require(pair.source.connect(pair.member.second.outputNumber, to: inlet))
        pair.sync()

        let samplerCopy = try #require(pair.counterpart(of: sampler))
        #expect(samplerCopy.strategy == PortType.Float.rawValue)
        #expect(pair.target.connections.count == 2)
        let copyID = samplerCopy.id

        sampler.strategy = PortType.Virtual.rawValue
        let rebuiltInlet = try #require(sampler.findPort(named: "inputValue", as: Port.self))
        #expect(rebuiltInlet !== inlet)
        #expect(rebuiltInlet.id == inlet.id)
        #expect(pair.source.connections.count == 2)
        #expect(pair.source.connections.contains {
            $0.outletPort === pair.member.second.outputNumber && $0.inletPort === rebuiltInlet
        })
        pair.syncExpectingNoUndo()

        let replaced = try #require(pair.counterpart(of: sampler))
        #expect(replaced !== samplerCopy)
        #expect(replaced.id == copyID)
        #expect(replaced.strategy == PortType.Virtual.rawValue)
        #expect(pair.target.nodes.contains { $0 === samplerCopy } == false)
        #expect(pair.target.connections.count == 2)
        let replacedInlet = try #require(replaced.findPort(named: "inputValue", as: Port.self))
        let secondCopy = try #require(pair.counterpart(of: pair.member.second))
        #expect(pair.target.connections.contains {
            $0.outletPort === secondCopy.outputNumber && $0.inletPort === replacedInlet
        })
    }

    @Test("Edits inside a nested subgraph reach the sibling's nested subgraph")
    func nestedEditsFollow() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        let deepAdded = NumberBinaryOperator(context: context)
        pair.member.nested.subGraph.addNode(deepAdded)
        _ = try #require(pair.member.nested.subGraph.connect(pair.member.nestedInner.outputNumber, to: deepAdded.inputNumber1))
        deepAdded.outputNumber.published = true
        pair.member.nested.subGraph.rebuildPublishedParameterGroup()
        let nestedProxy = try #require(pair.member.nested.ports.first { $0.id == deepAdded.outputNumber.id })
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
        let nestedProxyCopy = try #require(nestedCopy.ports.first { $0.id == deepCopy.outputNumber.id })
        let secondCopy = try #require(pair.counterpart(of: pair.member.second))
        #expect(pair.target.connections.contains {
            $0.outletPort === nestedProxyCopy && $0.inletPort === secondCopy.inputNumber2
        })
    }

    @Test("A sync refreshes the template, and a second sync with no edits changes nothing")
    func syncRefreshesTemplateAndIsIdempotent() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)
        let set = try #require(pair.graph.cloneSet(for: setID))
        let before = set.templateJSON

        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.sync()
        #expect(set.templateJSON != before)

        let report = try pair.graph.reconcileCloneMember(pair.sibling, from: pair.member.member)
        #expect(report.isEmpty)
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

    @Test("Sync is refused between a member and a member nested inside it")
    func syncSkipsNestedSelf() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        pair.graph.delete(node: pair.sibling)
        pair.source.addNode(pair.sibling)

        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.sync()

        #expect(pair.target.nodes.count == 3)
    }

    // MARK: Template as source

    @Test("A member can be made from the template alone, with the set's member class and a full record")
    func instantiateFromTemplate() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let iterator = IteratorNode(context: context)
        graph.addNode(iterator)
        let inner = NumberBinaryOperator(context: context)
        iterator.subGraph.addNode(inner)
        inner.outputNumber.published = true
        iterator.subGraph.rebuildPublishedParameterGroup()
        _ = try graph.duplicateAsClone(iterator)
        let setID = try #require(iterator.cloneSetID)

        let made = try graph.instantiateCloneSetMember(of: setID)

        #expect(made is IteratorNode)
        #expect(made.graph === graph)
        #expect(made.cloneSetID == setID)
        #expect(graph.cloneSetMembers(of: setID).count == 3)
        let madeInner = try #require(made.subGraph.nodes.first as? NumberBinaryOperator)
        #expect(madeInner.id != inner.id)
        #expect(madeInner.outputNumber.published)
        #expect(made.ports.contains { $0.id == madeInner.outputNumber.id && $0 is any ProxyPortProtocol })
        let templateID = try #require(iterator.templateID(forLocal: inner.id))
        #expect(made.localID(forTemplate: templateID) == madeInner.id)

        // It follows edits like any member.
        iterator.subGraph.addNode(NumberBinaryOperator(context: context))
        graph.reconcileCloneSiblings(of: iterator)
        #expect(made.subGraph.nodes.count == 2)
    }

    @Test("A member with no record is rebuilt from the template, keeping its parent wires by published name")
    func memberWithoutRecordIsRecovered() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        // Wire the sibling's published inlet from the parent graph.
        let upstream = NumberBinaryOperator(context: context)
        pair.graph.addNode(upstream)
        let proxy = try #require(pair.sibling.ports.first { $0.kind == .Inlet && $0.displayName == "Amount" })
        _ = try #require(pair.graph.connect(upstream.outputNumber, to: proxy))

        // Lose the record, as a document from before records would.
        pair.sibling.cloneRecord = [:]
        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.sync()

        let rebuilt = try #require(pair.graph.cloneSetMembers(of: pair.member.member.cloneSetID!).first { $0 !== pair.member.member })
        #expect(rebuilt.subGraph.nodes.count == 4)
        #expect(!rebuilt.cloneRecord.isEmpty)
        let rebuiltProxy = try #require(rebuilt.ports.first { $0.kind == .Inlet && $0.displayName == "Amount" })
        #expect(pair.graph.connections.contains { $0.outletPort === upstream.outputNumber && $0.inletPort === rebuiltProxy })
        #expect(pair.graph.nodes.contains { $0 === pair.sibling } == false)
    }

    @Test("A template updated from outside reconciles every member")
    func externalTemplateUpdateReconcilesMembers() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)

        // Produce a newer template from a third, independent member, then feed
        // its JSON back in as if it had arrived from a sidecar file.
        let scratch = Graph(context: context)
        let editor = try pair.graph.instantiateCloneSetMember(of: setID)
        pair.graph.delete(node: editor)
        scratch.addNode(editor)
        editor.subGraph.addNode(NumberBinaryOperator(context: context))
        let newTemplate = try #require(pair.graph.cloneTemplateJSON(from: editor))

        let reports = try pair.graph.applyCloneTemplate(newTemplate, to: setID)

        #expect(reports.count == 2)
        #expect(reports.allSatisfy { $0.nodesAdded == 1 })
        #expect(pair.source.nodes.count == 4)
        #expect(pair.target.nodes.count == 4)
        #expect(pair.graph.cloneSet(for: setID)?.templateJSON == newTemplate)
    }
}

// MARK: - Editor triggers

extension CloneSetTests
{
    // Canvas navigation is a main-thread affair, like the edits it flushes;
    // the fixtures are built off it so the run's other main-queue work is not
    // held up.
    @Test("Leaving a member's canvas syncs its siblings")
    func leavingMemberSyncs() async throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        await MainActor.run {
            let canvas = GraphCanvasContext(rootGraph: pair.graph)
            canvas.enter(pair.member.member)
            canvas.currentGraph.addNode(NumberBinaryOperator(context: context))
            #expect(pair.target.nodes.count == 3)

            canvas.pop()
        }

        #expect(pair.target.nodes.count == 4)
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

    @Test("Leaving a nested member syncs every enclosing set")
    func leavingNestedMemberSyncsEnclosingSets() async throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        await MainActor.run {
            let canvas = GraphCanvasContext(rootGraph: pair.graph)
            canvas.enter(pair.member.member)
            canvas.enter(pair.member.nested)
            canvas.currentGraph.addNode(NumberBinaryOperator(context: context))

            canvas.popToRoot()
        }

        let nestedCopy = try #require(pair.counterpart(of: pair.member.nested))
        #expect(nestedCopy.subGraph.nodes.count == 2)
    }
}

// MARK: - Live sync

extension CloneSetTests
{
    @Test("Edits inside a member bump its graph's content revision, through the member's own subscriptions")
    @MainActor
    func editsBumpContentRevision() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        var revision = pair.source.contentRevision

        func expectBump(_ what: String, sourceLocation: SourceLocation = #_sourceLocation)
        {
            #expect(pair.source.contentRevision > revision, "\(what) should bump", sourceLocation: sourceLocation)
            revision = pair.source.contentRevision
        }

        // Nodes present when the member joined the set are watched already.
        pair.member.second.offset = CGSize(width: 10, height: 10)
        expectBump("offset")
        pair.member.second.userName = "Renamed"
        expectBump("userName")
        pair.member.second.outputNumber.published = true
        expectBump("published")
        pair.member.second.outputNumber.publishedName = "Out"
        expectBump("publishedName")
        pair.member.second.inputNumber2.value = 42
        expectBump("unwired parameter value")
        pair.member.nestedInner.inputNumber2.value = 7
        expectBump("nested unwired parameter value")

        let added = NumberBinaryOperator(context: context)
        pair.source.addNode(added)
        expectBump("addNode")
        let connection = try #require(pair.source.connect(pair.member.second.outputNumber, to: added.inputNumber1))
        expectBump("connect")
        #expect(pair.source.setConnection(connection, active: false))
        expectBump("setConnection")
        #expect(pair.source.disconnect(connection))
        expectBump("disconnect")
        pair.source.addNote(Note(note: "n", rect: .zero))
        expectBump("addNote")
        pair.source.delete(node: added)
        expectBump("delete")
    }

    @Test("A node added after a sync is watched from the next sync on")
    @MainActor
    func subscriptionsFollowAddedNodes() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator

        let added = NumberBinaryOperator(context: context)
        pair.source.addNode(added)
        coordinator.flush()
        #expect(coordinator.hasPendingSync == false)

        added.inputNumber2.value = 3
        #expect(coordinator.hasPendingSync)
        coordinator.flush()
        let addedCopy = try #require(pair.counterpart(of: added))
        #expect(addedCopy.inputNumber2.value == 3)
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

        coordinator.flush()

        #expect(pair.target.nodes.count == 4)
        #expect(coordinator.hasPendingSync == false)
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
}

// MARK: - Fidelity

extension CloneSetTests
{
    /// Node types that need a device, a permission, a download or a file to
    /// construct; the encode/decode contract they rely on is the same.
    private static let liveSourceNamePattern = #"Camera|Audio|Screen|Syphon|Model|Movie|Video|Hand|Face|Pose|Vision|MIDI|OSC|Capture|Microphone|Speech|Image Loader|Loader|Recorder|Writer|Export"#

    @Test("Every core node type clones with nothing left for reconcile to change")
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
            guard let templateID = member.templateID(forLocal: node.id),
                  let localID = sibling.localID(forTemplate: templateID),
                  let copy = sibling.subGraph.node(forID: localID)
            else { mismatched.append("\(type(of: node)) did not clone"); continue }
            if copy.cloneSettingsSignature() != node.cloneSettingsSignature()
            {
                mismatched.append("\(type(of: node)) settings signature differs after cloning")
            }
        }
        #expect(mismatched.isEmpty, "\(mismatched)")

        let report = try graph.reconcileCloneMember(sibling, from: member)
        #expect(report.isEmpty, "\(report)")

        // A member made from the template alone matches too.
        let madeSetID = try #require(member.cloneSetID)
        let made = try graph.instantiateCloneSetMember(of: madeSetID)
        #expect(made.subGraph.nodes.count == member.subGraph.nodes.count)
        #expect(try graph.reconcileCloneMember(made, from: member).isEmpty)
    }
}

// MARK: - Review follow-ups

extension CloneSetTests
{
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

        #expect(pair.member.first.inputNumber2.value == 2)
        #expect(firstCopy.inputNumber2.value == 2)
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
        #expect(pair.sibling.cloneRecord.isEmpty)
        #expect(pair.graph.cloneSetMembers(of: setID).map(\.id) == [pair.member.member.id])
    }

    @Test("A settings change that keeps the ports bumps the revision and reaches the sibling")
    @MainActor
    func settingsChangeWithoutPortChangeSyncs() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator

        let expression = MathExpressionNode(context: context, expression: "sin(x) + y")
        pair.source.addNode(expression)
        coordinator.flush()
        let expressionCopy = try #require(pair.counterpart(of: expression))
        #expect(expressionCopy.stringExpression == "sin(x) + y")
        let revision = pair.source.contentRevision

        expression.stringExpression = "cos(x) + y"     // same ports, different design
        #expect(pair.source.contentRevision > revision)
        #expect(coordinator.hasPendingSync)
        coordinator.flush()

        let synced = try #require(pair.counterpart(of: expression))
        #expect(synced.stringExpression == "cos(x) + y")
    }
}

// MARK: - Failure paths

extension CloneSetTests
{
    @Test("The clone APIs throw typed errors rather than doing nothing")
    func apisThrow() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeMemberFixture(context: context)
        let elsewhere = Graph(context: context)

        #expect(throws: FabricError.self) { try elsewhere.duplicateAsClone(fixture.member) }
        #expect(throws: FabricError.self) { try fixture.graph.unlinkClone(fixture.member) }
        #expect(throws: FabricError.self) { try fixture.graph.renameCloneSet(UUID(), to: "X") }
        #expect(throws: FabricError.self) { try fixture.graph.instantiateCloneSetMember(of: UUID()) }
        #expect(throws: FabricError.self) { try fixture.graph.applyCloneTemplate(Data(), to: UUID()) }

        let sibling = try fixture.graph.duplicateAsClone(fixture.member)
        let stranger = SubgraphNode(context: context)
        fixture.graph.addNode(stranger)
        #expect(throws: FabricError.self) { try fixture.graph.reconcileCloneMember(stranger, from: fixture.member) }
        #expect(fixture.graph.nodes.contains { $0 === sibling })
    }
}

// MARK: - Storage by record

extension CloneSetTests
{
    /// Encodes the way the editor saves a document: members that match their
    /// set's template are written as their record and per-member values only.
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

    @Test("A saved document holds the template once and members as their record and per-member values")
    @MainActor
    func membersSaveByRecord() throws
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
        #expect(entries.allSatisfy { $0["cloneRecord"] != nil && $0["memberValues"] != nil })

        let decoded = try decode(data, context: context)
        let members = decoded.cloneSetMembers(of: setID)
        #expect(members.map(\.id) == [pair.member.member.id, pair.sibling.id])
        let decodedSibling = members[1]
        // Materialised through the record, so every id is the one the document knew.
        #expect(Set(decodedSibling.subGraph.nodesRecursive().map(\.id)) == Set(pair.sibling.subGraph.nodesRecursive().map(\.id)))
        let decodedFirstCopy = try #require(decodedSibling.subGraph.node(forID: firstCopy.id) as? NumberBinaryOperator)
        #expect(decodedFirstCopy.inputNumber1.value == 5)
        let decodedMemberFirst = try #require(members[0].subGraph.node(forID: pair.member.first.id) as? NumberBinaryOperator)
        #expect(decodedMemberFirst.inputNumber1.value == 1)
        // The parent's wire onto the sibling's proxy survived.
        let decodedUpstream = try #require(decoded.node(forID: upstream.id) as? NumberBinaryOperator)
        let decodedProxy = try #require(decodedSibling.ports.first { $0.id == proxy.id })
        #expect(decoded.connections.contains { $0.outletPort === decodedUpstream.outputNumber && $0.inletPort === decodedProxy })
        // The nested set came back too.
        #expect(decodedSibling.subGraph.nodes.compactMap { $0 as? SubgraphNode }.allSatisfy { $0.cloneSetID != nil })
        #expect(decoded.cloneSets.count == 2)
    }

    @Test("A member whose design has drifted from the template is saved in full, so nothing is lost")
    @MainActor
    func driftedMemberSavesInFull() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        pair.graph.cloneSetCoordinator.flush()

        // An edit the template has not seen: made, then the pending sync dropped.
        let added = NumberBinaryOperator(context: context)
        pair.target.addNode(added)
        pair.graph.cloneSetCoordinator.discardPendingSync()

        let data = try saveCompactly(pair.graph)
        let entries = try memberEntries(in: data)
        #expect(entries.filter { $0["subGraph"] == nil }.count == 1)
        #expect(entries.filter { $0["subGraph"] != nil }.count == 1)

        let decoded = try decode(data, context: context)
        let decodedSibling = try #require(decoded.node(forID: pair.sibling.id) as? SubgraphNode)
        #expect(decodedSibling.subGraph.nodes.count == 4)
        #expect(decodedSibling.subGraph.node(forID: added.id) != nil)
    }
}

// MARK: - Settings signature gate

extension CloneSetTests
{
    @Test("Nodes without settings are reconciled in place without an encode")
    func plainNodesSkipTheSignature() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let firstCopy = try #require(pair.counterpart(of: pair.member.first))

        pair.member.first.inputNumber2.value = 3
        let report = try pair.graph.reconcileCloneMember(pair.sibling, from: pair.member.member)

        #expect(report.nodesReplaced == 0)
        #expect(report.nodesUpdated == 1)
        #expect(firstCopy.inputNumber2.value == 3)
        #expect(pair.member.first.providesSettingsView() == false)
    }
}

// MARK: - Code review follow-ups

extension CloneSetTests
{
    @Test("Re-subscribing after syncs leaves one live watcher per port, not one per sync")
    @MainActor
    func observerRegistrationsDoNotAccumulate() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator

        for _ in 0..<5
        {
            pair.member.first.inputNumber2.value = (pair.member.first.inputNumber2.value ?? 0) + 1
            coordinator.flush()
        }

        let revision = pair.source.contentRevision
        pair.member.second.outputNumber.published.toggle()
        #expect(pair.source.contentRevision == revision + 1)
    }

    @Test("Unlinking a member nested inside a member reaches the siblings")
    @MainActor
    func nestedMembershipChangeSyncs() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator
        let nestedCopy = try pair.member.member.subGraph.duplicateAsClone(pair.member.nested)
        coordinator.flush()
        let siblingNested = try #require(pair.counterpart(of: pair.member.nested))
        #expect(siblingNested.cloneSetID != nil)

        try pair.source.unlinkClone(pair.member.nested)
        #expect(coordinator.hasPendingSync)
        coordinator.flush()

        #expect(siblingNested.cloneSetID == nil)
        #expect(try #require(pair.counterpart(of: nestedCopy)).cloneSetID != nil)
    }
}

// MARK: - Review round two

extension CloneSetTests
{
    @Test("A compact save keeps a member's own proxy state and nested per-member values")
    @MainActor
    func compactSaveKeepsProxyStateAndNestedValues() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let setID = try #require(pair.member.member.cloneSetID)
        pair.graph.cloneSetCoordinator.flush()

        // Publish one of the sibling's proxies onward, up into the root graph, and rename it there.
        let proxy = try #require(pair.sibling.ports.first { $0.kind == .Inlet && $0.displayName == "Amount" })
        proxy.published = true
        proxy.publishedName = "Root Amount"
        pair.graph.rebuildPublishedParameterGroup()

        // A published inlet two levels down, with a value of its own per member.
        pair.member.nestedInner.inputNumber1.published = true
        pair.member.nested.subGraph.rebuildPublishedParameterGroup()
        pair.graph.cloneSetCoordinator.flush()
        let nestedInnerCopy = try #require(pair.counterpart(of: pair.member.nestedInner))
        pair.member.nestedInner.inputNumber1.value = 7
        nestedInnerCopy.inputNumber1.value = 5
        pair.graph.cloneSetCoordinator.flush()

        let data = try saveCompactly(pair.graph)
        #expect(try memberEntries(in: data).allSatisfy { $0["subGraph"] == nil })
        let decoded = try decode(data, context: context)

        let decodedSibling = try #require(decoded.cloneSetMembers(of: setID).first { $0.id == pair.sibling.id })
        let decodedProxy = try #require(decodedSibling.ports.first { $0.id == proxy.id })
        #expect(decodedProxy.published)
        #expect(decodedProxy.publishedName == "Root Amount")
        #expect(decoded.publishedInputPorts().contains { $0.id == proxy.id })

        let decodedNestedInnerCopy = try #require(decodedSibling.subGraph.nodesRecursive().first { $0.id == nestedInnerCopy.id } as? NumberBinaryOperator)
        #expect(decodedNestedInnerCopy.inputNumber1.value == 5)
        let decodedMember = try #require(decoded.cloneSetMembers(of: setID).first { $0.id == pair.member.member.id })
        let decodedNestedInner = try #require(decodedMember.subGraph.nodesRecursive().first { $0.id == pair.member.nestedInner.id } as? NumberBinaryOperator)
        #expect(decodedNestedInner.inputNumber1.value == 7)
    }

    @Test("An edit inside a nested member syncs the nested set even when the outer member's graph is noted last")
    @MainActor
    func nestedEditSyncsInnerSetWhicheverObserverFiresLast() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator
        let nestedCopy = try pair.member.member.subGraph.duplicateAsClone(pair.member.nested)
        coordinator.flush()

        // The two observers fire in whichever order they subscribed; force the
        // outer member's note to arrive last, which is the order that lost the inner set.
        pair.member.nested.subGraph.noteContentChanged()
        pair.member.member.subGraph.noteContentChanged()
        pair.member.nestedInner.offset = CGSize(width: 99, height: 99)
        coordinator.flush()

        let nestedCopyInner = try #require(nestedCopy.subGraph.nodes.first as? NumberBinaryOperator)
        #expect(nestedCopyInner.offset == CGSize(width: 99, height: 99))
        let siblingNestedInner = try #require(pair.counterpart(of: pair.member.nestedInner))
        #expect(siblingNestedInner.offset == CGSize(width: 99, height: 99))
    }

    @Test("Recovering a member registers no undo step")
    @MainActor
    func recoveryRegistersNoUndo() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        pair.sibling.cloneRecord = [:]
        pair.source.addNode(NumberBinaryOperator(context: context))

        pair.syncExpectingNoUndo()

        #expect(pair.graph.cloneSetMembers(of: pair.member.member.cloneSetID!).count == 2)
    }

    @Test("Removing an outer member refreshes the badges of the nested set it took with it")
    @MainActor
    func nestedSetBadgesFollowOuterMembership() async throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let coordinator = pair.graph.cloneSetCoordinator
        _ = try pair.member.member.subGraph.duplicateAsClone(pair.member.nested)
        coordinator.flush()
        let nestedSetID = try #require(pair.member.nested.cloneSetID)
        #expect(pair.graph.cloneSetMembers(of: nestedSetID).count == 4)
        let nestedViewModel = pair.member.member.subGraph.viewModel(for: pair.member.nested)
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

    @Test("A pasted member is an ordinary subgraph")
    func pastedMemberCarriesNoLinks() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)

        pair.graph.copyNodesToPasteboard([pair.sibling])
        let pasted = pair.graph.pasteNodesFromPasteboard()

        let pastedMember = try #require(pasted.first as? SubgraphNode)
        #expect(pastedMember.cloneSetID == nil)
        #expect(pastedMember.cloneRecord.isEmpty)
        #expect(pastedMember.subGraph.subgraphNodesRecursive().allSatisfy { $0.cloneSetID == nil })
    }
}
