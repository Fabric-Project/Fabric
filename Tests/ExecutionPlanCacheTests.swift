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

/// The renderer keeps an execution plan per graph it has run, holding the
/// graph's nodes; a graph released takes its plan with it.
@Suite("Execution Plan Cache")
struct ExecutionPlanCacheTests
{
    @Test("A subgraph removed and released takes its nodes out of the renderer's plans")
    func releasedSubgraphReleasesItsNodes() throws
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
            try harness.execute(graph, frameNumber: 0)
            try harness.execute(graph, frameNumber: 1)
            #expect(node.executeCount > 0, "the inner graph ran, so the renderer has a plan for it")
            graph.delete(node: subgraph)
        }
        try harness.execute(graph, frameNumber: 2)
        #expect(innerGraph == nil)

        // The next plan made drops the released graph's.
        graph.addNode(NumberBinaryOperator(context: harness.context))
        try harness.execute(graph, frameNumber: 3)
        #expect(innerNode == nil)
    }
}
