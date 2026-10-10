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

    @Test("A published port replaced under its id gets a proxy over the replacement, and the parent's wire on it holds")
    func replacedPortGetsNewProxy() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let node = SampleAndHoldNode(context: context, initialStrategy: PortType.Float.rawValue)
        subgraph.subGraph.addNode(node)
        let value = try #require(node.findPort(named: "inputValue") as Fabric.Port?)
        subgraph.subGraph.setPublished(true, on: value)

        let upstream = NumberBinaryOperator(context: context)
        graph.addNode(upstream)
        let proxyBefore = try #require(subgraph.ports.first { $0.id == value.id })
        #expect(graph.connect(upstream.outputNumber, to: proxyBefore) != nil)

        node.strategy = PortType.Int.rawValue
        let replacement = try #require(node.findPort(named: "inputValue") as Fabric.Port?)
        #expect(replacement !== value)
        #expect(replacement.id == value.id)

        let proxyAfter = try #require(proxy(over: replacement.id, in: subgraph))
        #expect(proxyAfter.wraps(replacement))
        #expect(subgraph.ports.first { $0.id == value.id }?.portType == .Int)
        let liveProxy = subgraph.ports.first { $0.id == value.id }
        #expect(upstream.outputNumber.connections.count == 1)
        #expect(upstream.outputNumber.connections.first?.inletPort === liveProxy)
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

    @Test("A published port replaced with a type the parent's wire cannot take drops that wire")
    func replacementDropsAWireItCannotTake() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        graph.addNode(subgraph)
        let node = SampleAndHoldNode(context: context, initialStrategy: PortType.Float.rawValue)
        subgraph.subGraph.addNode(node)
        let value = try #require(node.findPort(named: "inputValue") as Fabric.Port?)
        subgraph.subGraph.setPublished(true, on: value)
        let upstream = NumberBinaryOperator(context: context)
        graph.addNode(upstream)
        let proxyPort = try #require(subgraph.ports.first { $0.id == value.id })
        #expect(graph.connect(upstream.outputNumber, to: proxyPort) != nil)

        node.strategy = PortType.Geometry.rawValue
        #expect(subgraph.ports.first { $0.id == value.id }?.portType == .Geometry)
        #expect(graph.connections.isEmpty)
        #expect(upstream.outputNumber.connections.isEmpty)
    }
}
