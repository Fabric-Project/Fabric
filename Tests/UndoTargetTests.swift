import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// An undo step finds what it acts on by id when it runs, so it acts on the
/// object standing under that id then, whatever put it there.
@Suite("Undo Targets")
@MainActor
struct UndoTargetTests
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

    private func makeUndoManager() -> UndoManager
    {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        return undoManager
    }

    /// One edit per group, as the editor's event loop makes them.
    private func step(_ undoManager: UndoManager, _ edit: () -> Void)
    {
        undoManager.beginUndoGrouping()
        edit()
        undoManager.endUndoGrouping()
    }

    /// `node` as another object under the same id, as a document load makes it.
    private func copy<N: Node>(of node: N, context: Context) throws -> N
    {
        let data = try JSONEncoder().encode(node)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        return try decoder.decode(N.self, from: data)
    }

    @Test("A wire one step puts back can be taken down by the step before it")
    func restoredWireUndoes() throws
    {
        guard let context = makeContext() else { return }
        let undoManager = makeUndoManager()
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        let inner = NumberBinaryOperator(context: context)
        let upstream = NumberBinaryOperator(context: context)
        graph.addNode(subgraph)
        graph.addNode(upstream)
        subgraph.subGraph.addNode(inner)
        subgraph.subGraph.setPublished(true, on: inner.inputNumber1)
        graph.undoManager = undoManager
        let proxy = try #require(subgraph.ports.first { $0.id == inner.inputNumber1.id })

        var wire: Connection?
        step(undoManager) { wire = graph.connect(upstream.outputNumber, to: proxy) }
        let wireID = try #require(wire?.id)
        step(undoManager) { subgraph.subGraph.setPublished(false, on: inner.inputNumber1) }
        #expect(graph.connections.isEmpty)

        undoManager.undo()
        #expect(graph.connections.map(\.id) == [wireID], "the wire comes back under its own id")
        undoManager.undo()
        #expect(graph.connections.isEmpty, "undoing the connect takes the wire the unpublish's undo put back")

        undoManager.redo()
        #expect(graph.connections.map(\.id) == [wireID])
        undoManager.redo()
        #expect(graph.connections.isEmpty)
    }

    @Test("A step acts on the node standing under its id when it runs")
    func stepFollowsNodeReplacedUnderItsID() throws
    {
        guard let context = makeContext() else { return }
        let undoManager = makeUndoManager()
        let graph = Graph(context: context)
        graph.undoManager = undoManager
        let node = NumberBinaryOperator(context: context)
        step(undoManager) { graph.addNode(node) }
        step(undoManager) {
            graph.registerOffsetChange(of: node, from: node.offset)
            node.offset = CGSize(width: 50, height: 0)
        }

        // Another object under the same id, put in without an undo step.
        let replacement = try copy(of: node, context: context)
        graph.withoutUndoRegistration {
            graph.delete(node: node)
            graph.addNode(replacement)
        }

        undoManager.undo()
        #expect(replacement.offset == .zero, "the move is undone on the node there now")
        undoManager.undo()
        #expect(graph.nodes.isEmpty, "undoing the add removes the node there now")
        undoManager.redo()
        #expect(graph.nodes.map(\.id) == [node.id])
    }

    @Test("Undoing a publish unpublishes the port replaced under its id since")
    func publishUndoFollowsReplacedPort() throws
    {
        guard let context = makeContext() else { return }
        let undoManager = makeUndoManager()
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let node = SampleAndHoldNode(context: context, initialStrategy: PortType.Float.rawValue)
        subgraph.subGraph.addNode(node)
        graph.undoManager = undoManager
        subgraph.subGraph.undoManager = undoManager
        let value = try #require(node.findPort(named: "inputValue") as Fabric.Port?)

        step(undoManager) { subgraph.subGraph.setPublished(true, on: value) }
        step(undoManager) { node.strategy = PortType.Int.rawValue }
        undoManager.undo()
        let live = try #require(node.findPort(named: "inputValue") as Fabric.Port?)
        #expect(live !== value)
        #expect(live.published)

        undoManager.undo()
        #expect(!live.published)
        #expect(!subgraph.ports.contains { $0.id == value.id })
    }

    @Test("Undoing a value edit sets the parameter of the port replaced under its id since")
    func valueUndoFollowsReplacedPort() throws
    {
        guard let context = makeContext() else { return }
        let undoManager = makeUndoManager()
        let graph = Graph(context: context)
        let node = SampleAndHoldNode(context: context, initialStrategy: PortType.Float.rawValue)
        graph.addNode(node)
        graph.undoManager = undoManager
        let port = try #require(node.findPort(named: "inputValue") as Fabric.Port?)
        let parameter = try #require(port.parameter as? GenericParameter<Float>)

        step(undoManager) {
            parameter.value = 3
            graph.registerValueChange(of: parameter, from: 0, label: "Value")
        }
        step(undoManager) { node.strategy = PortType.Int.rawValue }
        undoManager.undo()
        let live = try #require(node.findPort(named: "inputValue")?.parameter as? GenericParameter<Float>)
        #expect(live !== parameter)

        undoManager.undo()
        #expect(live.value == 0)
    }

    @Test("Create Subgraph undoes and redoes, and undoes again after a redo")
    func createSubgraphUndoRedoUndo() throws
    {
        guard let context = makeContext() else { return }
        let undoManager = makeUndoManager()
        let graph = Graph(context: context)
        let first = NumberBinaryOperator(context: context)
        let second = NumberBinaryOperator(context: context)
        graph.addNode(first)
        graph.addNode(second)
        graph.connect(first.outputNumber, to: second.inputNumber1)
        graph.undoManager = undoManager

        step(undoManager) {
            _ = try? graph.createSubgraph(from: [first, second], centeredOn: first, usingClass: SubgraphNode.self)
        }
        #expect(graph.nodes.count == 1)

        undoManager.undo()
        #expect(Set(graph.nodes.map(\.id)) == [first.id, second.id])
        #expect(graph.connections.count == 1)
        undoManager.redo()
        #expect(graph.nodes.count == 1)
        undoManager.undo()
        #expect(Set(graph.nodes.map(\.id)) == [first.id, second.id], "the redone embedding undoes")
        #expect(graph.connections.count == 1)
    }

    @Test("An edit in a graph the canvas has not given an undo manager records on the document's")
    func nestedGraphRecordsOnTheRootsUndoManager() throws
    {
        guard let context = makeContext() else { return }
        let undoManager = makeUndoManager()
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        graph.undoManager = undoManager
        #expect(subgraph.subGraph.undoManager == nil)

        step(undoManager) { subgraph.subGraph.addNode(NumberBinaryOperator(context: context)) }
        #expect(subgraph.subGraph.nodes.count == 1)
        undoManager.undo()
        #expect(subgraph.subGraph.nodes.isEmpty)
    }
}
