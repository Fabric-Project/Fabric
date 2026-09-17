import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// Which camera the scene draws through, once a graph contains a subgraph.
///
/// A subgraph runs its contents through the renderer it was handed, so `execute`
/// is re-entered with the inner graph, and the camera search descends into
/// subgraphs. Both make which camera reaches the scene depend on more than the
/// graph the scene belongs to.
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

    private func execute(_ renderer: GraphRenderer, _ graph: Graph) throws
    {
        let info = GraphExecutionInfo(timing: GraphExecutionTiming(
            time: 0, deltaTime: 1.0 / 60.0, displayTime: 0,
            systemTime: 0, hostMediaTime: 0, frameNumber: 0))
        let commandBuffer = try #require(renderer.commandQueue.makeCommandBuffer())
        try renderer.execute(graph: graph, executionInfo: info,
                             renderPassDescriptor: MTLRenderPassDescriptor(),
                             commandBuffer: commandBuffer)
    }

    @Test("A graph's camera is the one it draws through")
    func aGraphDrawsThroughItsOwnCamera() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let camera = PerspectiveCameraNode(context: context)
        graph.addNode(camera)

        let renderer = GraphRenderer(context: context, graph: graph)
        renderer.resize(size: (width: 320, height: 180), scaleFactor: 1)
        try execute(renderer, graph)

        #expect(renderer.currentCamera === camera.getObject())
    }

    /// The camera search descends into subgraphs, so a camera inside one is the
    /// scene's. Only the graph whose own nodes changed recomputes its caches, and
    /// a subgraph holds no reference to its parent, so the outer graph has to
    /// look rather than remember.
    @Test("A camera added inside a subgraph is the one the scene draws through")
    func aCameraInsideASubgraphIsUsed() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)

        let inner = CurrentTimeNode(context: context)
        graph.addNode(inner)
        let container = try graph.createSubgraph(from: [inner], centeredOn: inner,
                                                 usingClass: SubgraphNode.self)

        // As entering the subgraph and adding a camera there does.
        let camera = PerspectiveCameraNode(context: context)
        container.subGraph.addNode(camera)

        let renderer = GraphRenderer(context: context, graph: graph)
        renderer.resize(size: (width: 320, height: 180), scaleFactor: 1)
        try execute(renderer, graph)

        #expect(renderer.currentCamera === camera.getObject(),
                "the outer graph never looked again after the subgraph gained a camera")
    }

    @Test("Removing a subgraph's camera stops the scene drawing through it")
    func removingACameraInsideASubgraphIsNoticed() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)

        let inner = CurrentTimeNode(context: context)
        graph.addNode(inner)
        let container = try graph.createSubgraph(from: [inner], centeredOn: inner,
                                                 usingClass: SubgraphNode.self)

        let camera = PerspectiveCameraNode(context: context)
        container.subGraph.addNode(camera)

        let renderer = GraphRenderer(context: context, graph: graph)
        renderer.resize(size: (width: 320, height: 180), scaleFactor: 1)
        try execute(renderer, graph)
        try #require(renderer.currentCamera === camera.getObject())

        container.subGraph.delete(node: camera)
        try execute(renderer, graph)

        #expect(renderer.currentCamera !== camera.getObject(),
                "the scene kept drawing through a camera that is no longer in the graph")
    }

    @Test("A subgraph alongside it does not take the camera away")
    func aSubgraphDoesNotReplaceTheCamera() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)

        // Anything at all inside: what matters is that the subgraph runs, and
        // that what it runs has no camera of its own.
        let inner = CurrentTimeNode(context: context)
        graph.addNode(inner)
        _ = try graph.createSubgraph(from: [inner], centeredOn: inner,
                                     usingClass: SubgraphNode.self)

        let camera = PerspectiveCameraNode(context: context)
        graph.addNode(camera)

        let renderer = GraphRenderer(context: context, graph: graph)
        renderer.resize(size: (width: 320, height: 180), scaleFactor: 1)
        try execute(renderer, graph)

        #expect(renderer.currentCamera === camera.getObject(),
                "the subgraph's own camera-less graph replaced the scene's camera with the default")
    }
}
