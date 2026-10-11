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

    /// A port published two levels up: X inside `inner`, whose proxy is
    /// published inside `outer`, whose proxy is wired in `graph`.
    private struct TwoLevels
    {
        let graph: Graph
        let outer: SubgraphNode
        let inner: SubgraphNode
        let node: NumberBinaryOperator
        let upstream: NumberBinaryOperator
        let wire: Connection
    }

    private func makeTwoLevels(context: Context, node: NumberBinaryOperator? = nil) throws -> TwoLevels
    {
        let graph = Graph(context: context)
        let outer = SubgraphNode(context: context)
        let inner = SubgraphNode(context: context)
        let node = node ?? NumberBinaryOperator(context: context)
        let upstream = NumberBinaryOperator(context: context)
        graph.addNode(outer)
        graph.addNode(upstream)
        outer.subGraph.addNode(inner)
        inner.subGraph.addNode(node)
        inner.subGraph.setPublished(true, on: node.inputNumber1)
        let middle = try #require(inner.ports.first { $0.id == node.inputNumber1.id })
        outer.subGraph.setPublished(true, on: middle)
        outer.subGraph.setPublishedName("Gain", on: middle)
        let top = try #require(outer.ports.first { $0.id == node.inputNumber1.id })
        let wire = try #require(graph.connect(upstream.outputNumber, to: top))
        return TwoLevels(graph: graph, outer: outer, inner: inner, node: node, upstream: upstream, wire: wire)
    }

    @Test("Unpublishing takes the wires at every level the port is published up to, and undo puts each level back")
    func unpublishTakesTheWholeChain() throws
    {
        guard let context = makeContext() else { return }
        let undoManager = makeUndoManager()
        let levels = try makeTwoLevels(context: context)
        levels.graph.undoManager = undoManager
        let port = levels.node.inputNumber1

        step(undoManager) { levels.inner.subGraph.setPublished(false, on: port) }
        #expect(!levels.inner.ports.contains { $0.id == port.id })
        #expect(!levels.outer.ports.contains { $0.id == port.id }, "the proxy two levels up goes too")
        #expect(levels.graph.connections.isEmpty)
        #expect(levels.upstream.outputNumber.connections.isEmpty)

        undoManager.undo()
        let middle = try #require(levels.inner.ports.first { $0.id == port.id })
        #expect(middle.published)
        #expect(middle.publishedName == "Gain")
        let top = try #require(levels.outer.ports.first { $0.id == port.id })
        #expect(levels.graph.connections.map(\.id) == [levels.wire.id])
        #expect(levels.upstream.outputNumber.connections.first?.inletPort === top)
    }

    @Test("A published port a node removes takes the wires at every level it is published up to")
    func removedPortTakesTheWholeChain() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let outer = SubgraphNode(context: context)
        let inner = SubgraphNode(context: context)
        let node = MathExpressionNode(context: context, expression: "x")
        let upstream = NumberBinaryOperator(context: context)
        graph.addNode(outer)
        graph.addNode(upstream)
        outer.subGraph.addNode(inner)
        inner.subGraph.addNode(node)
        let x = try #require(node.inputPorts().first { $0.name == "x" })
        inner.subGraph.setPublished(true, on: x)
        let middle = try #require(inner.ports.first { $0.id == x.id })
        outer.subGraph.setPublished(true, on: middle)
        let top = try #require(outer.ports.first { $0.id == x.id })
        _ = try #require(graph.connect(upstream.outputNumber, to: top))

        node.stringExpression = "y"
        #expect(!outer.ports.contains { $0.id == x.id })
        #expect(graph.connections.isEmpty)
        #expect(upstream.outputNumber.connections.isEmpty)
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

    @Test("Undoing a delete puts back the publishing and wires at every level its ports were published up to")
    func deleteUndoRestoresTheWholeChain() throws
    {
        guard let context = makeContext() else { return }
        let undoManager = makeUndoManager()
        let levels = try makeTwoLevels(context: context)
        levels.graph.undoManager = undoManager
        let port = levels.node.inputNumber1

        step(undoManager) { levels.inner.subGraph.delete(node: levels.node) }
        #expect(!levels.outer.ports.contains { $0.id == port.id })

        undoManager.undo()
        let middle = try #require(levels.inner.ports.first { $0.id == port.id })
        #expect(middle.published)
        #expect(middle.publishedName == "Gain")
        let top = try #require(levels.outer.ports.first { $0.id == port.id })
        #expect(levels.graph.connections.map(\.id) == [levels.wire.id])
        #expect(levels.upstream.outputNumber.connections.first?.inletPort === top)

        undoManager.redo()
        #expect(!levels.outer.ports.contains { $0.id == port.id })
        undoManager.undo()
        #expect(levels.inner.ports.first { $0.id == port.id }?.published == true)
        #expect(levels.upstream.outputNumber.connections.first?.inletPort === levels.outer.ports.first { $0.id == port.id })
    }

    @Test("Unpublishing a proxy leaves the parameter it shares named as the port it stands for")
    func unpublishedProxyKeepsTheInnerLabel() throws
    {
        guard let context = makeContext() else { return }
        let levels = try makeTwoLevels(context: context)
        let port = levels.node.inputNumber1
        levels.inner.subGraph.setPublishedName("Amount", on: port)
        let middle = try #require(levels.inner.ports.first { $0.id == port.id })

        levels.outer.subGraph.setPublished(false, on: middle)
        #expect(port.parameter?.label == "Amount")
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
