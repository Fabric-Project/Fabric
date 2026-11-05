import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// `Node.graph` and `Connection.graph` are unowned. Reading one after its graph is gone would
/// trap, so each test holds nodes and connections past their graph's lifetime, or past their
/// removal, and reads the reference: it must read nil.
@Suite("Graph Unowned Lifetime")
struct GraphUnownedLifetimeTests
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

    @Test("Nodes and connections that outlive their graph read nil")
    func nodesAndConnectionsOutliveTheirGraph() throws
    {
        guard let context = makeContext() else { return }

        let source = NumberBinaryOperator(context: context)
        let sink = NumberBinaryOperator(context: context)
        weak var releasedGraph: Graph?
        var connection: Connection?
        do
        {
            let graph = Graph(context: context)
            releasedGraph = graph
            graph.addNode(source)
            graph.addNode(sink)
            connection = graph.connect(source.outputNumber, to: sink.inputNumber1)
            #expect(source.graph === graph)
            #expect(connection?.graph === graph)
        }

        #expect(releasedGraph == nil)
        #expect(source.graph == nil)
        #expect(sink.graph == nil)
        let heldConnection = try #require(connection)
        #expect(heldConnection.graph == nil)
    }

    @Test("A deleted node reads nil once its graph is gone")
    func deletedNodeOutlivesItsGraph()
    {
        guard let context = makeContext() else { return }

        let node = NumberBinaryOperator(context: context)
        weak var releasedGraph: Graph?
        do
        {
            let graph = Graph(context: context)
            releasedGraph = graph
            graph.addNode(node)
            graph.delete(node: node)
            #expect(node.graph == nil)
        }

        #expect(releasedGraph == nil)
        #expect(node.graph == nil)
    }

    @Test("A graph going away leaves a node another graph now holds")
    func movedNodeKeepsItsNewGraph()
    {
        guard let context = makeContext() else { return }

        let node = NumberBinaryOperator(context: context)
        let keptGraph = Graph(context: context)
        weak var releasedGraph: Graph?
        do
        {
            let graph = Graph(context: context)
            releasedGraph = graph
            graph.addNode(node)
            graph.delete(node: node)
            keptGraph.addNode(node)
        }

        #expect(releasedGraph == nil)
        #expect(node.graph === keptGraph)
    }

    @Test("Decoded nodes and connections read nil once their graph is gone")
    func decodedNodesOutliveTheirGraph() throws
    {
        guard let context = makeContext() else { return }

        let original = Graph(context: context)
        let source = NumberBinaryOperator(context: context)
        let sink = NumberBinaryOperator(context: context)
        original.addNode(source)
        original.addNode(sink)
        _ = try #require(original.connect(source.outputNumber, to: sink.inputNumber1))
        let data = try JSONEncoder().encode(original)

        var decodedNodes: [Node] = []
        var decodedConnections: [Connection] = []
        weak var releasedGraph: Graph?
        do
        {
            let decoder = JSONDecoder()
            decoder.context = DecoderContext(documentContext: context)
            let decoded = try decoder.decode(Graph.self, from: data)
            releasedGraph = decoded
            decodedNodes = decoded.nodes
            decodedConnections = decoded.connections
            #expect(decodedNodes.count == 2)
            #expect(decodedConnections.count == 1)
            #expect(decodedNodes.allSatisfy { $0.graph === decoded })
            #expect(decodedConnections.allSatisfy { $0.graph === decoded })
        }

        #expect(releasedGraph == nil)
        #expect(decodedNodes.allSatisfy { $0.graph == nil })
        #expect(decodedConnections.allSatisfy { $0.graph == nil })
    }
}
