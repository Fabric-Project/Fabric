import Foundation
import Combine
import Metal
import Testing
@testable import Fabric
import Satin

/// Edits a user makes register undo: publishing, naming a published port,
/// notes, and parameter values set through their controls.
@Suite("Edit Undo")
struct EditUndoTests
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

    /// One edit per group, as the editor's event loop makes them.
    private func step(_ undoManager: UndoManager, _ edit: () -> Void)
    {
        undoManager.beginUndoGrouping()
        edit()
        undoManager.endUndoGrouping()
    }

    private struct Fixture
    {
        let graph: Graph
        let container: SubgraphNode
        let inner: NumberBinaryOperator
        let upstream: NumberBinaryOperator
        let undoManager: UndoManager
    }

    /// A subgraph whose inner inlet is published, with the parent wired onto its proxy.
    private func makeFixture(context: Context) throws -> Fixture
    {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let graph = Graph(context: context)
        let container = SubgraphNode(context: context)
        let inner = NumberBinaryOperator(context: context)
        let upstream = NumberBinaryOperator(context: context)
        graph.addNode(container)
        graph.addNode(upstream)
        container.subGraph.addNode(inner)
        container.subGraph.setPublished(true, on: inner.inputNumber1)
        let proxy = try #require(container.ports.first { $0.id == inner.inputNumber1.id })
        _ = try #require(graph.connect(upstream.outputNumber, to: proxy))
        graph.undoManager = undoManager
        container.subGraph.undoManager = undoManager
        return Fixture(graph: graph, container: container, inner: inner, upstream: upstream, undoManager: undoManager)
    }

    @Test("Publishing and naming a published port are undo steps")
    func publishAndRenameUndo() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeFixture(context: context)
        let port = fixture.inner.inputNumber2

        step(fixture.undoManager) { fixture.container.subGraph.setPublished(true, on: port) }
        step(fixture.undoManager) { fixture.container.subGraph.setPublishedName("Gain", on: port) }
        #expect(fixture.container.ports.contains { $0.id == port.id && $0.displayName == "Gain" })
        #expect(fixture.undoManager.undoActionName == "Rename Port")

        fixture.undoManager.undo()
        #expect(port.publishedName == nil)
        fixture.undoManager.undo()
        #expect(!port.published)
        #expect(!fixture.container.ports.contains { $0.id == port.id })
    }

    @Test("Undoing a publish puts back the name the port carried unpublished, and redo publishes it under that name")
    func publishUndoKeepsTheName() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeFixture(context: context)
        let port = fixture.inner.inputNumber2
        let subGraph = fixture.container.subGraph
        step(fixture.undoManager) { subGraph.setPublishedName("Gain", on: port) }
        step(fixture.undoManager) { subGraph.setPublished(true, on: port) }
        #expect(fixture.container.ports.contains { $0.id == port.id && $0.displayName == "Gain" })
        #expect(fixture.undoManager.undoActionName == "Publish Port")

        fixture.undoManager.undo()
        #expect(!port.published)
        #expect(port.publishedName == "Gain")
        #expect(fixture.undoManager.redoActionName == "Publish Port")

        fixture.undoManager.redo()
        #expect(port.published)
        #expect(fixture.container.ports.contains { $0.id == port.id && $0.displayName == "Gain" })
        #expect(fixture.undoManager.undoActionName == "Publish Port")

        fixture.undoManager.undo()
        #expect(port.publishedName == "Gain")
        #expect(fixture.undoManager.redoActionName == "Publish Port")
        #expect(fixture.undoManager.undoActionName == "Rename Port", "the rename before it is the next step back")
    }

    @Test("Adding and deleting a node or a note keep their names through undo and redo")
    func addAndDeleteKeepTheirNames()
    {
        guard let context = makeContext() else { return }
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let graph = Graph(context: context)
        graph.undoManager = undoManager

        let node = NumberBinaryOperator(context: context)
        step(undoManager) { graph.addNode(node) }
        #expect(undoManager.undoActionName == "Add Node")
        undoManager.undo()
        #expect(undoManager.redoActionName == "Add Node")
        undoManager.redo()
        #expect(undoManager.undoActionName == "Add Node")

        step(undoManager) { graph.delete(node: node) }
        #expect(undoManager.undoActionName == "Delete Node")
        undoManager.undo()
        #expect(undoManager.redoActionName == "Delete Node")
        undoManager.redo()
        #expect(undoManager.undoActionName == "Delete Node")

        let note = Note(note: "Note", rect: .zero)
        step(undoManager) { graph.addNote(note) }
        #expect(undoManager.undoActionName == "Add Note")
        undoManager.undo()
        #expect(undoManager.redoActionName == "Add Note")
        undoManager.redo()
        #expect(undoManager.undoActionName == "Add Note")

        step(undoManager) { graph.deleteNote(note) }
        #expect(undoManager.undoActionName == "Delete Note")
        undoManager.undo()
        #expect(undoManager.redoActionName == "Delete Note")
        undoManager.redo()
        #expect(undoManager.undoActionName == "Delete Note")
    }

    @Test("Adding, editing and deleting a note are undo steps")
    func noteEditsUndo()
    {
        guard let context = makeContext() else { return }
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let graph = Graph(context: context)
        graph.undoManager = undoManager
        let first = Note(note: "First", rect: .zero)
        let note = Note(note: "Draft", rect: CGRect(x: 0, y: 0, width: 200, height: 100))

        step(undoManager) { graph.addNote(first) }
        step(undoManager) { graph.addNote(note) }
        step(undoManager) {
            note.note = "Final"
            note.rect.origin = CGPoint(x: 40, y: 40)
            graph.registerNoteEdit(note, previousText: "Draft", previousRect: CGRect(x: 0, y: 0, width: 200, height: 100))
        }
        step(undoManager) { graph.deleteNote(first) }
        #expect(graph.notes.map(\.id) == [note.id])

        undoManager.undo()
        #expect(graph.notes.map(\.id) == [first.id, note.id], "a deleted note comes back where it was")
        undoManager.undo()
        #expect(note.note == "Draft")
        #expect(note.rect.origin == .zero)
        undoManager.redo()
        #expect(note.note == "Final")
        undoManager.undo()
        undoManager.undo()
        #expect(graph.notes.map(\.id) == [first.id])
    }

    @Test("An edit recorded for a note after its delete is not a step")
    func noteEditAfterDeleteRegistersNothing()
    {
        guard let context = makeContext() else { return }
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let graph = Graph(context: context)
        graph.undoManager = undoManager
        let note = Note(note: "Draft", rect: .zero)
        step(undoManager) { graph.addNote(note) }

        note.note = "Typed"
        step(undoManager) { graph.deleteNote(note) }
        // The view going away ends the edit after the delete took the note.
        graph.registerNoteEdit(note, previousText: "Draft", previousRect: .zero)
        #expect(undoManager.undoActionName == "Delete Note")

        undoManager.undo()
        #expect(graph.notes.map(\.id) == [note.id])
        #expect(note.note == "Typed")
    }

    @Test("A parameter set through its control is one undo step per change, or per edit while one is in progress")
    @MainActor
    func parameterEditsUndo() throws
    {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let node = NumberBinaryOperator(context: context)
        graph.addNode(node)
        graph.undoManager = undoManager
        let parameter = try #require(node.inputNumber1.parameter as? FloatParameter)
        parameter.label = "Amount"
        parameter.value = 1
        let model = ParameterObservableModel(label: parameter.label,
                                             get: { parameter.value },
                                             set: { parameter.value = $0 },
                                             publisher: parameter.valuePublisher,
                                             graph: graph,
                                             undoParameter: parameter)

        // A discrete change.
        step(undoManager) { model.uiValue = 2 }
        #expect(undoManager.undoActionName == "Change Amount")

        // A drag: many changes, one step.
        step(undoManager) {
            model.setEditing(true)
            model.uiValue = 3
            model.uiValue = 4
            model.uiValue = 5
            model.setEditing(false)
        }

        undoManager.undo()
        #expect(parameter.value == 2)
        undoManager.undo()
        #expect(parameter.value == 1)
        #expect(!undoManager.canUndo)
        undoManager.redo()
        undoManager.redo()
        #expect(parameter.value == 5)
    }

    @Test("A momentary control's changes are not undo steps")
    @MainActor
    func untargetedParameterEditsRegisterNothing()
    {
        let parameter = BoolParameter("Fire", false, .button, "")
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        graph.undoManager = undoManager
        let model = ParameterObservableModel(label: parameter.label,
                                             get: { parameter.value },
                                             set: { parameter.value = $0 },
                                             publisher: parameter.valuePublisher,
                                             graph: graph)

        step(undoManager) { model.uiValue = true }
        undoManager.undo()
        #expect(parameter.value)
    }

    // MARK: - Changes a control holds

    private struct ParameterFixture
    {
        let graph: Graph
        let parameter: FloatParameter
        let undoManager: UndoManager
    }

    /// A number node's inlet, "Amount", at 1, in a graph with its own undo manager.
    private func makeParameterFixture(context: Context) throws -> ParameterFixture
    {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let graph = Graph(context: context)
        let node = NumberBinaryOperator(context: context)
        graph.addNode(node)
        graph.undoManager = undoManager
        let parameter = try #require(node.inputNumber1.parameter as? FloatParameter)
        parameter.label = "Amount"
        parameter.value = 1
        return ParameterFixture(graph: graph, parameter: parameter, undoManager: undoManager)
    }

    /// A control's model for the fixture's parameter.
    @MainActor
    private func makeModel(_ fixture: ParameterFixture, commit: EditCommit = .eachChange) -> ParameterObservableModel<Float>
    {
        ParameterObservableModel(label: fixture.parameter.label,
                                 get: { fixture.parameter.value },
                                 set: { fixture.parameter.value = $0 },
                                 publisher: fixture.parameter.valuePublisher,
                                 graph: fixture.graph,
                                 undoParameter: fixture.parameter,
                                 commit: commit)
    }

    @Test("A change made through a control is undone to the parameter's value before it, which the control's mirror can lag")
    @MainActor
    func parameterEditUndoesToTheParametersValue() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeParameterFixture(context: context)
        let model = makeModel(fixture)

        // The mirror follows the parameter on the main queue, so the control still shows 1.
        fixture.parameter.value = 2
        #expect(model.uiValue == 1)

        step(fixture.undoManager) {
            model.setEditing(true)
            model.uiValue = 3
            model.uiValue = 4
            model.setEditing(false)
        }
        fixture.graph.undo()
        #expect(fixture.parameter.value == 2)
        fixture.graph.redo()
        #expect(fixture.parameter.value == 4)
    }

    @Test("A change held while its control has focus is committed by undo, which takes it back rather than the step before, and the control carries on")
    @MainActor
    func heldEditIsCommittedByUndo() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeParameterFixture(context: context)
        let note = Note(note: "Earlier", rect: .zero)
        step(fixture.undoManager) { fixture.graph.addNote(note) }
        let model = makeModel(fixture)

        model.setEditing(true)
        model.uiValue = 2
        fixture.graph.undo()
        #expect(fixture.parameter.value == 1)
        #expect(fixture.graph.notes.map(\.id) == [note.id])
        fixture.graph.redo()
        #expect(fixture.parameter.value == 2)

        // Still focused: the next change is a new edit.
        model.uiValue = 3
        fixture.graph.undo()
        #expect(fixture.parameter.value == 2)
        fixture.graph.redo()
        #expect(fixture.parameter.value == 3)

        // Losing focus with nothing held adds no step.
        model.setEditing(false)
        fixture.graph.undo()
        #expect(fixture.parameter.value == 2)
        fixture.graph.undo()
        #expect(fixture.parameter.value == 1)
        fixture.graph.undo()
        #expect(fixture.graph.notes.isEmpty)
    }

    @Test("Undo is available while a control holds a change, and not once the change is returned to its start")
    @MainActor
    func heldEditMakesUndoAvailable() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeParameterFixture(context: context)
        let model = makeModel(fixture)
        #expect(!fixture.graph.canUndo)

        model.setEditing(true)
        model.uiValue = 2
        #expect(!fixture.undoManager.canUndo)
        #expect(fixture.graph.canUndo)
        model.uiValue = 1
        #expect(!fixture.graph.canUndo)
        model.setEditing(false)
        #expect(!fixture.undoManager.canUndo)
    }

    @Test("A change held for its pause is committed by its graph's undo, and left held by another graph's")
    @MainActor
    func pausedEditIsCommittedByItsGraphsUndo() throws
    {
        guard let context = makeContext() else { return }
        let first = try makeParameterFixture(context: context)
        let second = try makeParameterFixture(context: context)
        let firstModel = makeModel(first, commit: .afterPause)
        let secondModel = makeModel(second, commit: .afterPause)

        firstModel.uiValue = 2
        secondModel.uiValue = 2
        first.graph.undo()
        #expect(first.parameter.value == 1)
        #expect(second.parameter.value == 2)
        #expect(second.graph.canUndo)
        second.graph.undo()
        #expect(second.parameter.value == 1)
        first.graph.redo()
        #expect(first.parameter.value == 2)
    }

    // MARK: - Auto Layout

    @Test("Auto Layout is a step where it moves a node, and otherwise not one, leaving a redo standing")
    @MainActor
    func autoLayoutIsAStepOnlyWhereItMovesANode() throws
    {
        guard let context = makeContext() else { return }
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let graph = Graph(context: context)
        let node = NumberBinaryOperator(context: context)
        graph.addNode(node)
        graph.autoLayout()
        let laidOut = node.offset
        graph.undoManager = undoManager

        let note = Note(note: "Earlier", rect: .zero)
        step(undoManager) { graph.addNote(note) }
        graph.undo()
        #expect(undoManager.canRedo)

        graph.autoLayout()
        #expect(node.offset == laidOut)
        #expect(!undoManager.canUndo)
        #expect(undoManager.canRedo)
        graph.redo()
        #expect(graph.notes.map(\.id) == [note.id])

        let moved = CGSize(width: 333, height: 222)
        node.offset = moved
        graph.autoLayout()
        #expect(node.offset == laidOut)
        #expect(undoManager.undoActionName == "Auto Layout")
        graph.undo()
        #expect(node.offset == moved)
        #expect(undoManager.redoActionName == "Auto Layout")
        graph.redo()
        #expect(node.offset == laidOut)
    }
}
