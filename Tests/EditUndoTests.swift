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
}
