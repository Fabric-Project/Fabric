import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// A subgraph node's proxy forwards to the inner port it was made over, so a
/// published port a node removes or replaces takes its proxy with it.
@Suite("Proxy Port Replacement")
@MainActor
struct ProxyPortReplacementTests
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

    private func proxy(over portID: UUID, in subgraph: SubgraphNode) -> (any ProxyPortProtocol)?
    {
        subgraph.ports.lazy.compactMap { $0 as? any ProxyPortProtocol }.first { $0.innerPortID == portID }
    }

    @Test("A published port a node removes takes its proxy with it, and the parent's wire on the proxy")
    func removedPortTakesItsProxy() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let node = MathExpressionNode(context: context, expression: "x")
        subgraph.subGraph.addNode(node)
        let x = try #require(node.inputPorts().first { $0.name == "x" })
        subgraph.subGraph.setPublished(true, on: x)
        let upstream = NumberBinaryOperator(context: context)
        graph.addNode(upstream)
        let proxyPort = try #require(subgraph.ports.first { $0.id == x.id })
        #expect(graph.connect(upstream.outputNumber, to: proxyPort) != nil)

        node.stringExpression = "y"
        #expect(proxy(over: x.id, in: subgraph) == nil)
        #expect(graph.connections.isEmpty)
        #expect(upstream.outputNumber.connections.isEmpty)
    }

    @Test("An image node folding a published legacy output into its canonical one publishes the canonical through the graph, which gives it a proxy")
    func foldedLegacyImageOutputPublishesTheCanonicalOne() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let node = LiveImageNode(context: context)
        subgraph.subGraph.addNode(node)
        let canonical = try #require(node.findPort(named: "outputImage0", as: Fabric.Port.self))
        let legacy = NodePort<FabricImage>(name: "outputTexturePort", kind: .Outlet)
        node.addDynamicPort(legacy)
        subgraph.subGraph.setPublished(true, on: legacy)
        subgraph.subGraph.setPublishedName("Legacy", on: legacy)
        let legacyProxy = try #require(subgraph.ports.first { $0.id == legacy.id })
        let downstream = PassThroughNode<FabricImage>(context: context)
        graph.addNode(downstream)
        #expect(graph.connect(legacyProxy, to: downstream.input) != nil)
        graph.setPublished(true, on: legacyProxy)
        graph.setPublishedName("Picture", on: legacyProxy)

        node.postSetupSynchronizePorts(allowReplace: false)

        #expect(!node.ports.contains { $0 === legacy })
        #expect(canonical.published)
        #expect(canonical.publishedName == "Legacy")
        #expect(proxy(over: legacy.id, in: subgraph) == nil)
        #expect(!subgraph.ports.contains { $0.id == legacy.id })
        let canonicalProxies = subgraph.ports.filter { $0.id == canonical.id }
        #expect(canonicalProxies.count == 1)
        let canonicalProxy = try #require(canonicalProxies.first)
        #expect(proxy(over: canonical.id, in: subgraph) != nil)
        #expect(graph.connections.count == 1)
        #expect(downstream.input.connections.first?.outletPort === canonicalProxy, "the parent's wire moves to the canonical output's proxy")
        #expect(canonicalProxy.published)
        #expect(canonicalProxy.publishedName == "Picture")
        #expect(graph.getPublishedPorts().map(\.id) == [canonical.id])
    }

    @Test("Folding a legacy image output into a canonical one already published keeps the canonical's names and wires, and adds the legacy proxy's wire")
    func foldIntoPublishedCanonicalKeepsItsOwn() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let node = LiveImageNode(context: context)
        subgraph.subGraph.addNode(node)
        let canonical = try #require(node.findPort(named: "outputImage0", as: Fabric.Port.self))
        let legacy = NodePort<FabricImage>(name: "outputTexturePort", kind: .Outlet)
        node.addDynamicPort(legacy)

        subgraph.subGraph.setPublished(true, on: canonical)
        subgraph.subGraph.setPublishedName("Mine", on: canonical)
        subgraph.subGraph.setPublished(true, on: legacy)
        subgraph.subGraph.setPublishedName("Legacy", on: legacy)
        let canonicalProxy = try #require(subgraph.ports.first { $0.id == canonical.id })
        let legacyProxy = try #require(subgraph.ports.first { $0.id == legacy.id })

        let canonicalDownstream = PassThroughNode<FabricImage>(context: context)
        let legacyDownstream = PassThroughNode<FabricImage>(context: context)
        graph.addNode(canonicalDownstream)
        graph.addNode(legacyDownstream)
        let canonicalWire = try #require(graph.connect(canonicalProxy, to: canonicalDownstream.input))
        #expect(graph.connect(legacyProxy, to: legacyDownstream.input) != nil)
        graph.setPublished(true, on: canonicalProxy)
        graph.setPublishedName("Top", on: canonicalProxy)
        graph.setPublished(true, on: legacyProxy)
        graph.setPublishedName("Picture", on: legacyProxy)

        node.postSetupSynchronizePorts(allowReplace: false)

        #expect(!subgraph.ports.contains { $0.id == legacy.id })
        #expect(canonical.publishedName == "Mine")
        #expect(subgraph.ports.first { $0.id == canonical.id } === canonicalProxy)
        #expect(canonicalProxy.publishedName == "Top")
        #expect(canonicalDownstream.input.connections.first === canonicalWire)
        #expect(legacyDownstream.input.connections.first?.outletPort === canonicalProxy, "an outlet takes the legacy proxy's wire alongside its own")
        #expect(graph.connections.count == 2)
        #expect(graph.getPublishedPorts().map(\.id) == [canonical.id])
    }

    @Test("A saved proxy over a port no longer published is discarded at decode, leaving its inner port bound to no proxy")
    func savedProxyOverAnUnpublishedPortIsDiscarded() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let node = NumberBinaryOperator(context: context)
        subgraph.subGraph.addNode(node)
        subgraph.subGraph.setPublished(true, on: node.inputNumber1)
        // Saved with its proxy, but unpublished: a document whose sub graph
        // lost the publishing its proxy stood for.
        node.inputNumber1.setPublishing(false, name: nil)
        let data = try JSONEncoder().encode(graph)

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decodedGraph = try decoder.decode(Graph.self, from: data)
        let decodedSubgraph = try #require(decodedGraph.nodes.first { $0.id == subgraph.id } as? SubgraphNode)
        let decodedNode = try #require(decodedSubgraph.subGraph.nodes.first as? NumberBinaryOperator)

        #expect(!decodedSubgraph.ports.contains { $0.id == node.inputNumber1.id })
        #expect(decodedNode.inputNumber1.publishingProxyIdentifier == nil)
    }

    @Test("A same-type replacement under another name remakes the proxy under the new name, keeping the parent's wire")
    func renamedReplacementRemakesTheProxy() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let node = NumberBinaryOperator(context: context)
        subgraph.subGraph.addNode(node)
        let port = node.inputNumber1
        subgraph.subGraph.setPublished(true, on: port)
        let original = try #require(subgraph.ports.first { $0.id == port.id })
        let upstream = NumberBinaryOperator(context: context)
        graph.addNode(upstream)
        let wire = try #require(graph.connect(upstream.outputNumber, to: original))

        let replacement = PortType.Float.makeFreshPort(name: "Renamed", kind: .Inlet, description: "Renamed input", id: port.id)
        node.replacePort(port, with: replacement)

        let proxy = try #require(subgraph.ports.first { $0.id == port.id })
        #expect(proxy !== original)
        #expect(proxy.name == "Renamed")
        #expect(proxy.portDescription == "Renamed input")
        #expect(self.proxy(over: port.id, in: subgraph).map { $0.wraps(replacement) } == true)
        #expect(wire.inletPort === proxy)
        #expect(graph.connections.map(\.id) == [wire.id])
    }

    @Test("A legacy image output folded outside a graph, as at load, gives its name to a canonical one that has none")
    func legacyNameSurvivesAFoldOutsideAGraph() throws
    {
        guard let context = makeContext() else { return }
        let node = LiveImageNode(context: context)
        let canonical = try #require(node.findPort(named: "outputImage0", as: Fabric.Port.self))
        let legacy = NodePort<FabricImage>(name: "outputTexturePort", kind: .Outlet)
        legacy.setPublishing(true, name: "Legacy")
        node.addDynamicPort(legacy)

        node.postSetupSynchronizePorts(allowReplace: false)

        #expect(!node.ports.contains { $0 === legacy })
        #expect(canonical.published)
        #expect(canonical.publishedName == "Legacy")
    }

    @Test("A replaced port keeps its node's connected nodes, on both sides of the wire it keeps, and the node running")
    func replacedPortKeepsConnectedNodes() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let node = NumberBinaryOperator(context: harness.context)
        let downstream = NumberBinaryOperator(context: harness.context)
        graph.addNode(node)
        graph.addNode(downstream)
        let output = node.outputNumber
        let wire = try #require(graph.connect(output, to: downstream.inputNumber1))
        try renderer.startExecution()
        #expect(node.executionState == .started)

        let replacement = PortType.Float.makeFreshPort(name: output.name, kind: .Outlet, id: output.id)
        node.replacePort(output, with: replacement)
        try renderer.synchronizeLifecycle()

        #expect(graph.connections.first === wire)
        #expect(wire.outletPort === replacement)
        #expect(node.outputNodes.map(ObjectIdentifier.init) == [ObjectIdentifier(downstream)])
        #expect(downstream.inputNodes.map(ObjectIdentifier.init) == [ObjectIdentifier(node)])
        #expect(node.executionState == .started)
    }

    @Test("A proxy remade over a retyped port keeps its sub graph node's connected nodes")
    func remadeProxyKeepsConnectedNodes() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let node = NumberBinaryOperator(context: context)
        subgraph.subGraph.addNode(node)
        let output = node.outputNumber
        subgraph.subGraph.setPublished(true, on: output)
        let original = try #require(subgraph.ports.first { $0.id == output.id })
        let downstream = PassThroughNode<PortValue>(context: context)
        graph.addNode(downstream)
        let wire = try #require(graph.connect(original, to: downstream.input))

        let replacement = PortType.Bool.makeFreshPort(name: output.name, kind: .Outlet, id: output.id)
        node.replacePort(output, with: replacement)

        let remade = try #require(subgraph.ports.first { $0.id == output.id })
        #expect(remade !== original)
        #expect(wire.outletPort === remade)
        #expect(subgraph.outputNodes.map(ObjectIdentifier.init) == [ObjectIdentifier(downstream)])
        #expect(downstream.inputNodes.map(ObjectIdentifier.init) == [ObjectIdentifier(subgraph)])
    }

    @Test("A replacement built published takes the replaced port's state, unpublished, and gets no proxy")
    func replacementBuiltPublishedTakesTheReplacedState() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let node = NumberBinaryOperator(context: context)
        subgraph.subGraph.addNode(node)
        let port = node.inputNumber1
        let replacement = PortType.Float.makeFreshPort(name: port.name, kind: .Inlet, id: port.id)
        replacement.setPublishing(true, name: "Built")

        node.replacePort(port, with: replacement)

        #expect(!replacement.published)
        #expect(!subgraph.ports.contains { $0.id == port.id })
        #expect(subgraph.subGraph.getPublishedPorts().isEmpty)
        #expect(subgraph.subGraph.publishedParameterGroup.params.isEmpty)
    }
}
