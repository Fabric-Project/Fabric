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

    @Test("Undoing an unpublish brings back the proxy, its name and publish in the parent, and the parent's wire")
    func unpublishUndoes() throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeFixture(context: context)
        let proxy = try #require(fixture.container.ports.first { $0.id == fixture.inner.inputNumber1.id })
        proxy.published = true
        proxy.publishedName = "Speed"
        fixture.inner.inputNumber1.publishedName = "Amount"

        step(fixture.undoManager) { fixture.container.subGraph.setPublished(false, on: fixture.inner.inputNumber1) }
        #expect(fixture.graph.connections.isEmpty)
        #expect(fixture.undoManager.undoActionName == "Unpublish Port")

        fixture.undoManager.undo()
        #expect(fixture.inner.inputNumber1.published)
        #expect(fixture.inner.inputNumber1.publishedName == "Amount")
        let restored = try #require(fixture.container.ports.first { $0.id == fixture.inner.inputNumber1.id })
        #expect(restored.published)
        #expect(restored.publishedName == "Speed")
        #expect(fixture.graph.connections.count == 1)
        #expect(fixture.upstream.outputNumber.connections.first?.inletPort === restored)

        fixture.undoManager.redo()
        #expect(!fixture.inner.inputNumber1.published)
        #expect(fixture.graph.connections.isEmpty)
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

    @Test("A parameter set through its control is one undo step per change, or per edit while one is in progress")
    @MainActor
    func parameterEditsUndo()
    {
        let parameter = FloatParameter("Amount", 1, 0, 10, .slider, "")
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let model = ParameterObservableModel(label: parameter.label,
                                             get: { parameter.value },
                                             set: { parameter.value = $0 },
                                             publisher: parameter.valuePublisher,
                                             undoManager: undoManager,
                                             undoTarget: parameter)

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
        let model = ParameterObservableModel(label: parameter.label,
                                             get: { parameter.value },
                                             set: { parameter.value = $0 },
                                             publisher: parameter.valuePublisher,
                                             undoManager: undoManager)

        step(undoManager) { model.uiValue = true }
        undoManager.undo()
        #expect(parameter.value)
    }

    @Test("Duplicating a node leaves a UUID-shaped string value as it is")
    func duplicateKeepsUUIDShapedValues() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let node = StringLengthNode(context: context)
        graph.addNode(node)
        let text = UUID().uuidString
        node.inputPort.value = text

        let copy = try #require(graph.duplicateNodes([node]).first as? StringLengthNode)
        #expect(copy.id != node.id)
        #expect(copy.inputPort.id != node.inputPort.id)
        #expect(copy.inputPort.value == text)
    }

    @Test("A note keeps its id across a save")
    func noteIDSurvivesASave() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let note = Note(note: "Kept", rect: CGRect(x: 1, y: 2, width: 3, height: 4))
        graph.addNote(note)

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(Graph.self, from: try JSONEncoder().encode(graph))
        #expect(decoded.notes.map(\.id) == [note.id])
    }
}
