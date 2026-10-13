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

    @Test("A compound edit in a graph with no undo manager of its own groups and names its steps on the document's")
    func nestedCompoundEditsGroupOnTheRootsUndoManager() throws
    {
        guard let context = makeContext() else { return }
        let undoManager = makeUndoManager()
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let inner = subgraph.subGraph
        let source = NumberBinaryOperator(context: context)
        let first = NumberBinaryOperator(context: context)
        let second = NumberBinaryOperator(context: context)
        for node in [source, first, second] { inner.addNode(node) }
        inner.connect(source.outputNumber, to: first.inputNumber1)
        inner.connect(source.outputNumber, to: second.inputNumber1)
        graph.undoManager = undoManager
        #expect(inner.undoManager == nil)
        let nodeIDs = Set(inner.nodes.map(\.id))
        let connectionIDs = Set(inner.connections.map(\.id))

        // No group is open: each edit must open its own, or registering throws.
        inner.insertParameterNode(for: first.inputNumber2)
        #expect(inner.nodes.count == 4)
        #expect(undoManager.undoActionName == "Insert Parameter Node")
        undoManager.undo()
        #expect(!undoManager.canUndo, "one step")
        #expect(Set(inner.nodes.map(\.id)) == nodeIDs)
        #expect(Set(inner.connections.map(\.id)) == connectionIDs)

        inner.disconnectAll(from: source.outputNumber)
        #expect(inner.connections.isEmpty)
        #expect(undoManager.undoActionName == "Disconnect Ports")
        undoManager.undo()
        #expect(undoManager.canRedo && !undoManager.canUndo, "one step")
        #expect(Set(inner.connections.map(\.id)) == connectionIDs)
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
    @Test("Undoing a delete puts the node back where it stood among the graph's nodes")
    func deleteUndoKeepsNodeOrder() throws
    {
        guard let context = makeContext() else { return }
        let undoManager = makeUndoManager()
        let graph = Graph(context: context)
        let nodes = (0..<3).map { _ in NumberBinaryOperator(context: context) }
        nodes.forEach(graph.addNode)
        graph.undoManager = undoManager

        step(undoManager) { graph.delete(node: nodes[1]) }
        undoManager.undo()
        #expect(graph.nodes.map(\.id) == nodes.map(\.id))
    }

    @Test("Suspending registration in a graph with no undo manager of its own suspends the root's it records on")
    func withoutUndoRegistrationSuspendsTheRootsManager() throws
    {
        guard let context = makeContext() else { return }
        let undoManager = makeUndoManager()
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        graph.undoManager = undoManager

        // No group is open: a step registered here would raise.
        subgraph.subGraph.withoutUndoRegistration {
            subgraph.subGraph.addNode(NumberBinaryOperator(context: context))
        }
        #expect(!undoManager.canUndo)
    }
}
