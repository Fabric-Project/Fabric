import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// A sub graph node's proxies follow its sub graph's published set through
/// the events the sub graph raises, at every level a port is published up to,
/// and undo and redo of each edit put every level back.
@Suite("Publishing Events")
@MainActor
struct PublishingEventsTests
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

    /// `node` inside `inner`, inside `outer`, inside `graph`, with an undo
    /// manager for `graph`, which the sub graphs record on, for a test to
    /// give it once its fixture is built.
    private struct Levels
    {
        let graph: Graph
        let outer: SubgraphNode
        let inner: SubgraphNode
        let undoManager: UndoManager
    }

    private func makeLevels(context: Context, around node: Node) -> Levels
    {
        let graph = Graph(context: context)
        let outer = SubgraphNode(context: context)
        let inner = SubgraphNode(context: context)
        graph.addNode(outer)
        outer.subGraph.addNode(inner)
        inner.subGraph.addNode(node)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        return Levels(graph: graph, outer: outer, inner: inner, undoManager: undoManager)
    }

    /// Publishes `port` in the inner graph and its proxy in the outer one,
    /// returning the proxies at both levels.
    private func publishTwoLevels(_ port: Fabric.Port, in levels: Levels) throws -> (middle: Fabric.Port, top: Fabric.Port)
    {
        levels.inner.subGraph.setPublished(true, on: port)
        let middle = try #require(levels.inner.ports.first { $0.id == port.id })
        levels.outer.subGraph.setPublished(true, on: middle)
        let top = try #require(levels.outer.ports.first { $0.id == port.id })
        return (middle, top)
    }

    private func wraps(_ proxy: Fabric.Port?, _ port: Fabric.Port) -> Bool
    {
        (proxy as? any ProxyPortProtocol)?.wraps(port) == true
    }

    @Test("Publishing makes a proxy over the port under its id at each level, and undo and redo take and make each")
    func publishMakesAProxyAtEachLevel() throws
    {
        guard let context = makeContext() else { return }
        let node = NumberBinaryOperator(context: context)
        let levels = makeLevels(context: context, around: node)
        levels.graph.undoManager = levels.undoManager
        let port = node.inputNumber1

        step(levels.undoManager) { levels.inner.subGraph.setPublished(true, on: port) }
        let middle = try #require(levels.inner.ports.first { $0.id == port.id })
        #expect(wraps(middle, port))
        #expect(middle.node === levels.inner)
        #expect(!middle.published)

        step(levels.undoManager) { levels.outer.subGraph.setPublished(true, on: middle) }
        let top = try #require(levels.outer.ports.first { $0.id == port.id })
        #expect(wraps(top, middle))

        levels.undoManager.undo()
        #expect(!levels.outer.ports.contains { $0.id == port.id })
        #expect(!middle.published)
        levels.undoManager.undo()
        #expect(!levels.inner.ports.contains { $0.id == port.id })
        #expect(!port.published)

        levels.undoManager.redo()
        let redoneMiddle = try #require(levels.inner.ports.first { $0.id == port.id })
        #expect(wraps(redoneMiddle, port))
        levels.undoManager.redo()
        #expect(redoneMiddle.published)
        #expect(wraps(levels.outer.ports.first { $0.id == port.id }, redoneMiddle))
    }

    @Test("Unpublishing takes the wires off the proxy at each level up, and undo and redo put them back and take them again")
    func unpublishTakesEachLevel() throws
    {
        guard let context = makeContext() else { return }
        let node = NumberBinaryOperator(context: context)
        let levels = makeLevels(context: context, around: node)
        let port = node.inputNumber1
        let upstream = NumberBinaryOperator(context: context)
        levels.graph.addNode(upstream)
        let undoManager = levels.undoManager
        let (middle, top) = try publishTwoLevels(port, in: levels)
        levels.outer.subGraph.setPublishedName("Gain", on: middle)
        let wire = try #require(levels.graph.connect(upstream.outputNumber, to: top))
        levels.graph.undoManager = undoManager

        step(undoManager) { levels.inner.subGraph.setPublished(false, on: port) }
        #expect(!levels.inner.ports.contains { $0.id == port.id })
        #expect(!levels.outer.ports.contains { $0.id == port.id })
        #expect(levels.graph.connections.isEmpty)
        #expect(upstream.outputNumber.connections.isEmpty)
        #expect(levels.outer.subGraph.publishedParameterGroup.params.isEmpty)

        undoManager.undo()
        let restoredMiddle = try #require(levels.inner.ports.first { $0.id == port.id })
        #expect(restoredMiddle.published)
        #expect(restoredMiddle.publishedName == "Gain")
        let restoredTop = try #require(levels.outer.ports.first { $0.id == port.id })
        #expect(levels.graph.connections.map(\.id) == [wire.id])
        #expect(upstream.outputNumber.connections.first?.inletPort === restoredTop)

        undoManager.redo()
        #expect(!levels.outer.ports.contains { $0.id == port.id })
        #expect(levels.graph.connections.isEmpty)

        undoManager.undo()
        let againTop = try #require(levels.outer.ports.first { $0.id == port.id })
        #expect(levels.graph.connections.map(\.id) == [wire.id])
        #expect(upstream.outputNumber.connections.first?.inletPort === againTop)
    }

    @Test("A published port its node removes takes its proxy at each level up, with the wires on them, as steps of their own")
    func removedPortTakesEachLevel() throws
    {
        guard let context = makeContext() else { return }
        let node = MathExpressionNode(context: context, expression: "x")
        let levels = makeLevels(context: context, around: node)
        let x = try #require(node.inputPorts().first { $0.name == "x" })
        let upstream = NumberBinaryOperator(context: context)
        levels.graph.addNode(upstream)
        let undoManager = levels.undoManager
        let (_, top) = try publishTwoLevels(x, in: levels)
        _ = try #require(levels.graph.connect(upstream.outputNumber, to: top))
        levels.graph.undoManager = undoManager

        step(undoManager) { node.stringExpression = "y" }
        #expect(!levels.inner.ports.contains { $0.id == x.id })
        #expect(!levels.outer.ports.contains { $0.id == x.id })
        #expect(levels.graph.connections.isEmpty)
        #expect(upstream.outputNumber.connections.isEmpty)
        #expect(levels.inner.subGraph.publishedParameterGroup.params.isEmpty)
        #expect(levels.outer.subGraph.publishedParameterGroup.params.isEmpty)
        #expect(undoManager.canUndo, "the wire and the publishing the proxies took are steps")
    }

    @Test("Renaming a published port renames the parameter its proxies share, at each level it is published up to")
    func renameRefreshesEachLevel() throws
    {
        guard let context = makeContext() else { return }
        let node = NumberBinaryOperator(context: context)
        let levels = makeLevels(context: context, around: node)
        let port = node.inputNumber1
        let undoManager = levels.undoManager
        let (middle, top) = try publishTwoLevels(port, in: levels)
        levels.graph.undoManager = undoManager
        let parameter = try #require(port.parameter)

        step(undoManager) { levels.inner.subGraph.setPublishedName("Gain", on: port) }
        #expect(middle.displayName == "Gain")
        #expect(top.displayName == "Gain")
        #expect(parameter.label == "Gain")
        #expect(levels.outer.subGraph.publishedParameterGroup.params.contains { $0 === parameter })

        undoManager.undo()
        #expect(top.displayName == port.name)
        #expect(parameter.label == port.name)

        undoManager.redo()
        #expect(top.displayName == "Gain")
        #expect(parameter.label == "Gain")
    }

    @Test("A node added with a published port gets a proxy, and undoing the add takes it")
    func addedNodeWithAPublishedPortGetsAProxy() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        graph.undoManager = undoManager

        let node = NumberBinaryOperator(context: context)
        node.inputNumber1.setPublishing(true, name: "Speed")
        step(undoManager) { subgraph.subGraph.addNode(node) }
        let proxy = try #require(subgraph.ports.first { $0.id == node.inputNumber1.id })
        #expect(wraps(proxy, node.inputNumber1))
        #expect(proxy.displayName == "Speed")

        undoManager.undo()
        #expect(!subgraph.ports.contains { $0.id == node.inputNumber1.id })
        undoManager.redo()
        #expect(subgraph.ports.contains { $0.id == node.inputNumber1.id })

        var copies: [Node] = []
        step(undoManager) { copies = subgraph.subGraph.duplicateNodes([node]) }
        let copy = try #require(copies.first as? NumberBinaryOperator)
        #expect(wraps(subgraph.ports.first { $0.id == copy.inputNumber1.id }, copy.inputNumber1), "a duplicate's published port gets a proxy of its own")
    }

    @Test("Deleting a node is one undo step that puts back its wires and its proxies at each level, and redo takes them again")
    func deleteIsOneStepAcrossLevels() throws
    {
        guard let context = makeContext() else { return }
        let node = NumberBinaryOperator(context: context)
        let levels = makeLevels(context: context, around: node)
        let port = node.inputNumber1
        let upstream = NumberBinaryOperator(context: context)
        let feeder = NumberBinaryOperator(context: context)
        levels.graph.addNode(upstream)
        levels.inner.subGraph.addNode(feeder)
        let undoManager = levels.undoManager
        let (_, top) = try publishTwoLevels(port, in: levels)
        let outerWire = try #require(levels.graph.connect(upstream.outputNumber, to: top))
        let innerWire = try #require(levels.inner.subGraph.connect(node.outputNumber, to: feeder.inputNumber1))
        levels.graph.undoManager = undoManager
        #expect(!undoManager.canUndo)

        step(undoManager) { levels.inner.subGraph.delete(node: node) }
        #expect(levels.inner.subGraph.connections.isEmpty)
        #expect(levels.graph.connections.isEmpty)
        #expect(!levels.outer.ports.contains { $0.id == port.id })

        undoManager.undo()
        #expect(!undoManager.canUndo, "the delete and what it took are one step")
        #expect(levels.inner.subGraph.connections.map(\.id) == [innerWire.id])
        #expect(levels.graph.connections.map(\.id) == [outerWire.id])
        #expect(upstream.outputNumber.connections.first?.inletPort === levels.outer.ports.first { $0.id == port.id })

        undoManager.redo()
        #expect(levels.inner.subGraph.connections.isEmpty)
        #expect(levels.graph.connections.isEmpty)
        #expect(!levels.inner.ports.contains { $0.id == port.id })

        undoManager.undo()
        #expect(levels.graph.connections.map(\.id) == [outerWire.id])
        #expect(levels.inner.subGraph.connections.map(\.id) == [innerWire.id])
    }

    @Test("Undoing Insert Parameter Node puts the port's publishing back, its proxy and the wire on it")
    func insertParameterNodeUndoRestoresPublishing() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        let node = NumberBinaryOperator(context: context)
        let upstream = NumberBinaryOperator(context: context)
        graph.addNode(subgraph)
        graph.addNode(upstream)
        subgraph.subGraph.addNode(node)
        let port = node.inputNumber1
        subgraph.subGraph.setPublished(true, on: port)
        subgraph.subGraph.setPublishedName("Amount", on: port)
        let proxy = try #require(subgraph.ports.first { $0.id == port.id })
        let wire = try #require(graph.connect(upstream.outputNumber, to: proxy))
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        graph.undoManager = undoManager

        step(undoManager) { subgraph.subGraph.insertParameterNode(for: port) }
        let parameterNode = try #require(subgraph.subGraph.nodes.first { $0 !== node })
        let parameterInlet = try #require(parameterNode.inputPorts().first)
        #expect(!port.published)
        #expect(port.publishedName == nil)
        #expect(parameterInlet.published)
        #expect(parameterInlet.publishedName == "Amount")
        #expect(!subgraph.ports.contains { $0.id == port.id })
        #expect(subgraph.ports.contains { $0.id == parameterInlet.id })

        undoManager.undo()
        #expect(port.published)
        #expect(port.publishedName == "Amount")
        #expect(subgraph.subGraph.nodes.map(\.id) == [node.id])
        let restoredProxy = try #require(subgraph.ports.first { $0.id == port.id })
        #expect(!subgraph.ports.contains { $0.id == parameterInlet.id })
        #expect(graph.connections.map(\.id) == [wire.id])
        #expect(upstream.outputNumber.connections.first?.inletPort === restoredProxy)

        undoManager.redo()
        #expect(!port.published)
        #expect(subgraph.subGraph.nodes.count == 2)
    }
}
