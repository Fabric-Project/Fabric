import Testing
import Metal
@testable import Fabric
import Satin

@Suite("Renderer camera selection")
struct RendererCameraSelectionTests
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

    private func execute(_ renderer: GraphRenderer, graph: Graph) throws
    {
        let executionInfo = GraphExecutionInfo(timing: GraphExecutionTiming(
            time: 0,
            deltaTime: 1.0 / 60.0,
            displayTime: 0,
            systemTime: 0,
            hostMediaTime: 0,
            frameNumber: 0
        ))
        let commandBuffer = try #require(renderer.commandQueue.makeCommandBuffer())
        try renderer.execute(graph: graph,
                             executionInfo: executionInfo,
                             renderPassDescriptor: MTLRenderPassDescriptor(),
                             commandBuffer: commandBuffer)
    }

    private func makeSubgraph(in graph: Graph, context: Context) throws -> SubgraphNode
    {
        let innerNode = CurrentTimeNode(context: context)
        graph.addNode(innerNode)
        return try graph.createSubgraph(from: [innerNode],
                                        centeredOn: innerNode,
                                        usingClass: SubgraphNode.self)
    }

    @Test("A graph draws through its own camera")
    func graphDrawsThroughItsOwnCamera() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let cameraNode = PerspectiveCameraNode(context: context)
        graph.addNode(cameraNode)

        let renderer = GraphRenderer(context: context, graph: graph)
        try execute(renderer, graph: graph)

        #expect(renderer.currentCamera === cameraNode.getObject())
    }

    @Test("A camera added inside an existing subgraph updates its containing graph")
    func cameraAddedInsideSubgraphIsUsed() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraphNode = try makeSubgraph(in: graph, context: context)
        let cameraNode = PerspectiveCameraNode(context: context)

        subgraphNode.subGraph.addNode(cameraNode)

        let renderer = GraphRenderer(context: context, graph: graph)
        try execute(renderer, graph: graph)

        #expect(renderer.currentCamera === cameraNode.getObject())
    }

    @Test("Publishing a subgraph outlet does not hide its camera")
    func publishingSubgraphOutletDoesNotHideCamera() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let subgraphNode = try makeSubgraph(in: graph, context: context)
        let cameraNode = PerspectiveCameraNode(context: context)
        subgraphNode.subGraph.addNode(cameraNode)

        let innerTimeNode = try #require(subgraphNode.subGraph.nodes.first as? CurrentTimeNode)
        innerTimeNode.outputNumber.published = true
        subgraphNode.subGraph.rebuildPublishedParameterGroup()
        try #require(subgraphNode.nodeExecutionMode != .Consumer)

        let renderer = GraphRenderer(context: context, graph: graph)
        try execute(renderer, graph: graph)

        #expect(renderer.currentCamera === cameraNode.getObject())
    }

    @Test("Removing a subgraph camera invalidates every containing graph")
    func removingNestedCameraIsNoticed() throws
    {
        guard let context = makeContext() else { return }
        let outerGraph = Graph(context: context)
        let outerSubgraphNode = try makeSubgraph(in: outerGraph, context: context)
        let innerSubgraphNode = try makeSubgraph(in: outerSubgraphNode.subGraph, context: context)
        let cameraNode = PerspectiveCameraNode(context: context)
        innerSubgraphNode.subGraph.addNode(cameraNode)

        let renderer = GraphRenderer(context: context, graph: outerGraph)
        try execute(renderer, graph: outerGraph)
        try #require(renderer.currentCamera === cameraNode.getObject())

        innerSubgraphNode.subGraph.delete(node: cameraNode)
        try execute(renderer, graph: outerGraph)

        #expect(renderer.currentCamera !== cameraNode.getObject())
    }

    @Test("Nested execution does not replace the outer graph camera")
    func nestedExecutionPreservesOuterCamera() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        _ = try makeSubgraph(in: graph, context: context)
        let cameraNode = PerspectiveCameraNode(context: context)
        graph.addNode(cameraNode)

        let renderer = GraphRenderer(context: context, graph: graph)
        try execute(renderer, graph: graph)

        #expect(renderer.currentCamera === cameraNode.getObject())
    }

    @Test("A deferred subgraph keeps its camera isolated")
    func deferredSubgraphCameraIsIsolated() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let deferredSubgraphNode = DeferredSubgraphNode(context: context)
        let cameraNode = PerspectiveCameraNode(context: context)
        deferredSubgraphNode.subGraph.addNode(cameraNode)

        graph.addNode(deferredSubgraphNode)

        #expect(graph.latestCamera == nil)
    }
}
