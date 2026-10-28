import Foundation
import Testing
import Metal
@testable import Fabric

private final class CountingConsumer: Node
{
    override class var name: String { "Counting Consumer" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override class var nodeTimeMode: Node.TimeMode { .None }

    private(set) var executeCount = 0

    override func execute(renderer: GraphRenderer,
                          executionInfo: GraphExecutionInfo,
                          renderPassDescriptor: MTLRenderPassDescriptor,
                          commandBuffer: MTLCommandBuffer) throws
    {
        executeCount += 1
    }
}

/// The renderer keeps an execution plan per graph it has run, holding the graph's nodes. Removing a
/// subgraph node is a membership edit, so the next lifecycle review releases its inner graphs' plans.
@Suite("Execution Plan Cache")
struct ExecutionPlanCacheTests
{
    @Test("A deleted subgraph's inner graph and nodes are released after the next frame")
    func deletedSubgraphReleasesItsPlan() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        try harness.graphRenderer(for: graph).startExecution()
        weak var innerNode: CountingConsumer?
        weak var innerGraph: Graph?
        do
        {
            let subgraph = SubgraphNode(context: harness.context)
            let node = CountingConsumer(context: harness.context)
            subgraph.subGraph.addNode(node)
            graph.addNode(subgraph)
            innerNode = node
            innerGraph = subgraph.subGraph
            _ = try harness.execute(graph, frameNumber: 0)
            _ = try harness.execute(graph, frameNumber: 1)
            #expect(node.executeCount > 0, "the inner graph ran, so the renderer has a plan for it")
            graph.delete(node: subgraph)
        }
        _ = try harness.execute(graph, frameNumber: 2)
        #expect(innerGraph == nil)
        #expect(innerNode == nil)
    }

    @Test("A deleted subgraph nested in another releases its plan too")
    func deletedNestedSubgraphReleasesItsPlan() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        try harness.graphRenderer(for: graph).startExecution()
        weak var nestedGraph: Graph?
        weak var nestedNode: CountingConsumer?
        do
        {
            let outer = SubgraphNode(context: harness.context)
            let nested = SubgraphNode(context: harness.context)
            let node = CountingConsumer(context: harness.context)
            nested.subGraph.addNode(node)
            outer.subGraph.addNode(nested)
            graph.addNode(outer)
            nestedGraph = nested.subGraph
            nestedNode = node
            _ = try harness.execute(graph, frameNumber: 0)
            _ = try harness.execute(graph, frameNumber: 1)
            #expect(node.executeCount > 0, "the nested graph ran, so the renderer has a plan for it")
            graph.delete(node: outer)
        }
        _ = try harness.execute(graph, frameNumber: 2)
        #expect(nestedGraph == nil)
        #expect(nestedNode == nil)
    }
}
