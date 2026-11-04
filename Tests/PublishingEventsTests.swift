import Combine
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
    /// manager for a test to give every level once its fixture is built, as
    /// the canvas gives each graph it shows.
    private struct Levels
    {
        let graph: Graph
        let outer: SubgraphNode
        let inner: SubgraphNode
        let undoManager: UndoManager

        func recordEdits()
        {
            for graph in [graph, outer.subGraph, inner.subGraph] { graph.undoManager = undoManager }
        }
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
        levels.recordEdits()
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
        levels.recordEdits()

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
        levels.recordEdits()

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
        levels.recordEdits()
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
        subgraph.subGraph.undoManager = undoManager

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
        levels.recordEdits()
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
        subgraph.subGraph.undoManager = undoManager

        step(undoManager) { subgraph.subGraph.insertParameterNode(for: port) }
        let parameterNode = try #require(subgraph.subGraph.nodes.first { $0 !== node })
        let parameterInlet = try #require(parameterNode.inputPorts().first)
        #expect(!port.published)
        #expect(port.publishedName == nil)
        #expect(parameterInlet.published)
        #expect(parameterInlet.publishedName == "Amount")
        #expect(!subgraph.ports.contains { $0.id == port.id })
        let parameterProxy = try #require(subgraph.ports.first { $0.id == parameterInlet.id })
        #expect(graph.connections.count == 1)
        #expect(upstream.outputNumber.connections.first?.inletPort === parameterProxy, "the parent's wire moves to the parameter port's proxy")

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
        let redoneParameterInlet = try #require(subgraph.subGraph.nodes.first { $0 !== node }?.inputPorts().first)
        #expect(upstream.outputNumber.connections.first?.inletPort === subgraph.ports.first { $0.id == redoneParameterInlet.id })
    }

    @Test("Insert Parameter Node moves the wires and publishing on the port's proxies, at each level up, to the parameter port's")
    func insertParameterNodeCarriesEachLevel() throws
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
        levels.recordEdits()

        step(undoManager) { levels.inner.subGraph.insertParameterNode(for: port) }
        let parameterInlet = try #require(levels.inner.subGraph.nodes.first { $0 !== node }?.inputPorts().first)
        let parameterMiddle = try #require(levels.inner.ports.first { $0.id == parameterInlet.id })
        #expect(!levels.inner.ports.contains { $0.id == port.id })
        #expect(parameterMiddle.published)
        #expect(parameterMiddle.publishedName == "Gain")
        #expect(!middle.published)
        let parameterTop = try #require(levels.outer.ports.first { $0.id == parameterInlet.id })
        #expect(wraps(parameterTop, parameterMiddle))
        #expect(!levels.outer.ports.contains { $0.id == port.id })
        #expect(levels.graph.connections.count == 1)
        #expect(upstream.outputNumber.connections.first?.inletPort === parameterTop)

        undoManager.undo()
        let restoredMiddle = try #require(levels.inner.ports.first { $0.id == port.id })
        #expect(restoredMiddle.published)
        #expect(restoredMiddle.publishedName == "Gain")
        let restoredTop = try #require(levels.outer.ports.first { $0.id == port.id })
        #expect(!levels.outer.ports.contains { $0.id == parameterInlet.id })
        #expect(levels.graph.connections.map(\.id) == [wire.id])
        #expect(upstream.outputNumber.connections.first?.inletPort === restoredTop)

        undoManager.redo()
        let redoneInlet = try #require(levels.inner.subGraph.nodes.first { $0 !== node }?.inputPorts().first)
        let redoneTop = try #require(levels.outer.ports.first { $0.id == redoneInlet.id })
        #expect(upstream.outputNumber.connections.first?.inletPort === redoneTop)
        #expect(levels.inner.ports.first { $0.id == redoneInlet.id }?.publishedName == "Gain")
    }

    @Test("Renaming a port through a graph it is not in changes nothing")
    func renameThroughAnotherGraphIsRefused() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        let node = NumberBinaryOperator(context: context)
        graph.addNode(subgraph)
        subgraph.subGraph.addNode(node)
        let port = node.inputNumber1
        subgraph.subGraph.setPublished(true, on: port)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        graph.undoManager = undoManager

        step(undoManager) { graph.setPublishedName("Gain", on: port) }
        #expect(port.publishedName == nil)
        #expect(subgraph.ports.first { $0.id == port.id }?.displayName == port.name)
        #expect(undoManager.undoActionName.isEmpty, "no rename step is registered")
    }

    @Test("A replacement port of the proxy's value type gives the proxy its value")
    func retargetedProxyTakesTheReplacementsValue() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        let node = NumberBinaryOperator(context: context)
        graph.addNode(subgraph)
        subgraph.subGraph.addNode(node)
        let port = node.inputNumber1
        port.value = 3
        subgraph.subGraph.setPublished(true, on: port)
        let proxy = try #require(subgraph.ports.first { $0.id == port.id } as? NodePort<Float>)
        #expect(proxy.value == 3)

        let replacement = try #require(PortType.Float.makeFreshPort(name: port.name, kind: .Inlet, id: port.id) as? NodePort<Float>)
        replacement.value = 7
        node.replacePort(port, with: replacement)

        #expect(subgraph.ports.first { $0.id == port.id } === proxy, "a proxy of the same value type is kept")
        #expect(wraps(proxy, replacement))
        #expect(proxy.value == 7)
        #expect(replacement.value == 7)
    }

    @Test("Adding or deleting a node with several published ports changes its sub graph node's ports once, and the published parameters around it once")
    func severalPublishedPortsChangeTheProxiesOnce() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let node = NumberBinaryOperator(context: context)
        node.inputNumber1.setPublishing(true, name: nil)
        node.inputNumber2.setPublishing(true, name: nil)
        node.outputNumber.setPublishing(true, name: nil)

        var changes = 0
        let subscription = subgraph.portsChangedSubject.sink { changes += 1 }
        defer { subscription.cancel() }

        subgraph.subGraph.addNode(node)
        #expect(subgraph.ports.filter { $0 is any ProxyPortProtocol }.count == 3)
        #expect(changes == 1)

        for proxy in subgraph.ports where proxy is any ProxyPortProtocol
        {
            graph.setPublished(true, on: proxy)
        }
        #expect(graph.getPublishedPorts().count == 3)
        var parentRebuilds = 0
        let rebuildSubscription = graph.publishedParameterGroup.clearedPublisher.sink { _ in parentRebuilds += 1 }
        defer { rebuildSubscription.cancel() }

        changes = 0
        subgraph.subGraph.delete(node: node)
        #expect(!subgraph.ports.contains { $0 is any ProxyPortProtocol })
        #expect(changes == 1)
        #expect(graph.getPublishedPorts().isEmpty)
        #expect(parentRebuilds == 1)
    }

    @Test("Moving wires onto an inlet already wired leaves both inlets as they were")
    func transferWiresKeepsAWiredInletsWire() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let retiring = NumberBinaryOperator(context: context)
        let replacement = NumberBinaryOperator(context: context)
        let first = NumberBinaryOperator(context: context)
        let second = NumberBinaryOperator(context: context)
        [retiring, replacement, first, second].forEach { graph.addNode($0) }
        let retiringWire = try #require(graph.connect(first.outputNumber, to: retiring.inputNumber1))
        let ownWire = try #require(graph.connect(second.outputNumber, to: replacement.inputNumber1))

        graph.transferWires(from: retiring.inputNumber1, to: replacement.inputNumber1)

        #expect(replacement.inputNumber1.connections.map(\.id) == [ownWire.id])
        #expect(retiring.inputNumber1.connections.map(\.id) == [retiringWire.id])
    }

    @Test("A node decoding into a graph raises no publishing there until the graph adds it, which publishes its port once")
    func decodedNodeRaisesNothingBeforeItIsAdded() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let source = MathExpressionNode(context: context, expression: "x + 1")
        let x = try #require(source.findPort(named: "x", as: Fabric.Port.self))
        x.setPublishing(true, name: "Gain")
        let data = try JSONEncoder().encode(source)

        let decoder = JSONDecoder()
        let decodeContext = DecoderContext(documentContext: context)
        decodeContext.currentGraph = subgraph.subGraph
        decoder.context = decodeContext
        _ = subgraph.subGraph.takeNodesAwaitingLifecycleReview()

        let decoded = try decoder.decode(MathExpressionNode.self, from: data)
        let decodedX = try #require(decoded.findPort(named: "x", as: Fabric.Port.self))
        #expect(decodedX.published)
        #expect(decoded.graph === subgraph.subGraph, "the decode names the graph before the graph adds the node")
        #expect(subgraph.subGraph.takeNodesAwaitingLifecycleReview().isEmpty)
        #expect(subgraph.subGraph.publishedParameterGroup.params.isEmpty)
        #expect(!subgraph.ports.contains { $0.id == x.id })

        let a = try #require(decoded.findPort(named: "x", as: Fabric.Port.self))
        subgraph.subGraph.setPublished(false, on: a)
        subgraph.subGraph.setPublishedName("Other", on: a)
        #expect(a.published, "the publishing API refuses a node the graph has not added")
        #expect(a.publishedName == "Gain")
        #expect(subgraph.subGraph.takeNodesAwaitingLifecycleReview().isEmpty)
        #expect(subgraph.subGraph.publishedParameterGroup.params.isEmpty)

        subgraph.subGraph.addNode(decoded)
        #expect(subgraph.ports.filter { $0.id == x.id }.count == 1)
        let parameter = try #require(decodedX.parameter)
        #expect(subgraph.subGraph.publishedParameterGroup.params.filter { $0 === parameter }.count == 1)
    }

    @Test("A loaded document's sub graph publishes a dynamic port once, with one proxy over it")
    func loadedDynamicPortIsPublishedOnce() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let node = MathExpressionNode(context: context, expression: "x + 1")
        subgraph.subGraph.addNode(node)
        let x = try #require(node.findPort(named: "x", as: Fabric.Port.self))
        subgraph.subGraph.setPublished(true, on: x)
        let data = try JSONEncoder().encode(graph)

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decodedGraph = try decoder.decode(Graph.self, from: data)
        let decodedSubgraph = try #require(decodedGraph.nodes.first { $0.id == subgraph.id } as? SubgraphNode)
        let decodedNode = try #require(decodedSubgraph.subGraph.nodes.first { $0.id == node.id })
        let decodedX = try #require(decodedNode.findPort(named: "x", as: Fabric.Port.self))
        let parameter = try #require(decodedX.parameter)

        #expect(decodedSubgraph.subGraph.getPublishedPorts().map(\.id) == [x.id])
        #expect(decodedSubgraph.subGraph.publishedParameterGroup.params.filter { $0 === parameter }.count == 1)
        #expect(decodedSubgraph.ports.filter { $0.id == x.id }.count == 1)
        #expect(wraps(decodedSubgraph.ports.first { $0.id == x.id }, decodedX))
    }

    @Test("A port replaced under its id keeps a name it carries unpublished")
    func replacementKeepsAnUnpublishedName() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let node = MathExpressionNode(context: context, expression: "x + 1")
        graph.addNode(node)
        let x = try #require(node.findPort(named: "x", as: Fabric.Port.self))
        graph.setPublished(true, on: x)
        graph.setPublishedName("Gain", on: x)
        graph.setPublished(false, on: x)
        graph.setPublishedName("Gain", on: x)
        #expect(!x.published)
        #expect(x.publishedName == "Gain")

        node.stringExpression = "in x: vec3; out o = x + vec3(1)"
        let retyped = try #require(node.findPort(named: "x", as: Fabric.Port.self))
        #expect(retyped !== x)
        #expect(retyped.id == x.id)
        #expect(!retyped.published)
        #expect(retyped.publishedName == "Gain")
    }

    @Test("Naming an unpublished port changes nothing in the published set")
    func namingAnUnpublishedPortRebuildsNothing() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let node = NumberBinaryOperator(context: context)
        subgraph.subGraph.addNode(node)
        var rebuilds = 0
        let subscription = subgraph.subGraph.publishedParameterGroup.clearedPublisher.sink { _ in rebuilds += 1 }
        defer { subscription.cancel() }
        let revision = subgraph.subGraph.connectionRevision

        subgraph.subGraph.setPublishedName("Carried", on: node.inputNumber1)

        #expect(node.inputNumber1.publishedName == "Carried")
        #expect(rebuilds == 0)
        #expect(subgraph.subGraph.connectionRevision == revision)

        subgraph.subGraph.setPublished(true, on: node.inputNumber1)
        #expect(subgraph.ports.first { $0.id == node.inputNumber1.id }?.displayName == "Carried")
    }

    @Test("Moving wires onto a port they do not fit leaves them where they are")
    func transferWiresLeavesAWireThatDoesNotFit() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let retiring = NumberBinaryOperator(context: context)
        let replacement = PassThroughNode<FabricImage>(context: context)
        let upstream = NumberBinaryOperator(context: context)
        [retiring, replacement, upstream].forEach { graph.addNode($0) }
        let wire = try #require(graph.connect(upstream.outputNumber, to: retiring.inputNumber1))

        graph.transferWires(from: retiring.inputNumber1, to: replacement.input)

        #expect(graph.connections.map(\.id) == [wire.id])
        #expect(retiring.inputNumber1.connections.map(\.id) == [wire.id])
        #expect(replacement.input.connections.isEmpty)
    }
}
