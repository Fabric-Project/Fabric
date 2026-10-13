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

}
