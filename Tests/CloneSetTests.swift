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

        // Mirrors arrive on the main queue; poll briefly rather than sleep a fixed time.
        func settle(until condition: @escaping () -> Bool) async throws
        {
            for _ in 0..<50 where !condition()
            {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        let sibling = try #require(fixture.graph.duplicateAsClone(fixture.member))
        try await settle { viewModel.titleIcon?.tooltip.contains("2 members") == true }
        #expect(viewModel.titleIcon?.tooltip.contains("2 members") == true)
        #expect(viewModel.subtitle == "Set A")

        fixture.member.userName = "Left"
        try await settle { viewModel.subtitle == "Left" }
        #expect(viewModel.subtitle == "Left")
        #expect(viewModel.titleIcon?.tooltip.contains("Set A") == true)

        fixture.graph.delete(node: sibling)
        try await settle { viewModel.titleIcon?.tooltip.contains("1 member.") == true }
        #expect(viewModel.titleIcon?.tooltip.contains("1 member.") == true)
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
        let sibling = try #require(member.graph.duplicateAsClone(member.member))
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
        #expect(pair.sibling.localID(forTemplate: pair.member.member.templateID(forLocal: added.inputNumber2.id)!) == addedCopy.inputNumber2.id)
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
        #expect(pair.source.connections.count == 1)
        let rebuiltInlet = try #require(sampler.findPort(named: "inputValue", as: Port.self))
        _ = try #require(pair.source.connect(pair.member.second.outputNumber, to: rebuiltInlet))
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
        let set = try #require(pair.graph.cloneSet(for: pair.member.member.cloneSetID!))
        let before = set.templateJSON

        pair.source.addNode(NumberBinaryOperator(context: context))
        pair.sync()
        #expect(set.templateJSON != before)

        let report = pair.graph.reconcileCloneMember(pair.sibling, from: pair.member.member)
        #expect(report.isEmpty)
    }

    @Test("An unlinked member no longer follows")
    func unlinkedStopsFollowing() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        pair.graph.unlinkClone(pair.sibling)

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
        _ = try #require(graph.duplicateAsClone(iterator))
        let setID = try #require(iterator.cloneSetID)

        let made = try #require(graph.instantiateCloneSetMember(of: setID))

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
        let editor = try #require(pair.graph.instantiateCloneSetMember(of: setID))
        pair.graph.delete(node: editor)
        scratch.addNode(editor)
        editor.subGraph.addNode(NumberBinaryOperator(context: context))
        let newTemplate = try #require(pair.graph.cloneTemplateJSON(from: editor))

        let reports = pair.graph.applyCloneTemplate(newTemplate, to: setID)

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
    @Test("Leaving a member's canvas syncs its siblings")
    func leavingMemberSyncs() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let canvas = GraphCanvasContext(rootGraph: pair.graph)

        canvas.enter(pair.member.member)
        canvas.currentGraph.addNode(NumberBinaryOperator(context: context))
        #expect(pair.target.nodes.count == 3)

        canvas.pop()

        #expect(pair.target.nodes.count == 4)
    }

    @Test("Leaving a nested member syncs every enclosing set")
    func leavingNestedMemberSyncsEnclosingSets() throws
    {
        guard let context = makeContext() else { return }
        let pair = try makePair(context: context)
        let canvas = GraphCanvasContext(rootGraph: pair.graph)

        canvas.enter(pair.member.member)
        canvas.enter(pair.member.nested)
        canvas.currentGraph.addNode(NumberBinaryOperator(context: context))

        canvas.popToRoot()

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

        pair.graph.unlinkClone(pair.sibling)
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

        let sibling = try #require(graph.duplicateAsClone(member))
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

        let report = graph.reconcileCloneMember(sibling, from: member)
        #expect(report.isEmpty, "\(report)")

        // A member made from the template alone matches too.
        let made = try #require(graph.instantiateCloneSetMember(of: member.cloneSetID!))
        #expect(made.subGraph.nodes.count == member.subGraph.nodes.count)
        #expect(graph.reconcileCloneMember(made, from: member).isEmpty)
    }
}
