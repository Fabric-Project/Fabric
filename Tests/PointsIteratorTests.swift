import Testing
import Metal
import simd
@testable import Fabric
import Satin

/// Published points inside an Iterator and Render to Image: every iteration publishes its own
/// points into one shared geometry, and each recorded draw keeps the points it was recorded with,
/// so N iterations draw exactly what N separate geometries draw.
@Suite("Points in Iterators")
struct PointsIteratorTests
{
    private static let offsets: [Float] = [-0.5, 0.5]

    private func makeIteratorGraph(_ harness: GraphExecutionTestHarness) -> Graph
    {
        let graph = Graph(context: harness.context)
        let iterator = IteratorNode(context: harness.context)
        iterator.inputIteratonCount.value = Self.offsets.count
        addPointsMesh(to: iterator.subGraph, context: harness.context, offsets: Self.offsets)
        graph.addNode(iterator)
        return graph
    }

    /// One separate points mesh per offset, outside any Iterator.
    private func makeReferenceGraph(_ harness: GraphExecutionTestHarness, offsets: [Float]) -> Graph
    {
        let graph = Graph(context: harness.context)
        for offset in offsets { addPointsMesh(to: graph, context: harness.context, offsets: Self.offsets, fixedOffset: offset) }
        return graph
    }

    private func render(_ graph: Graph, _ harness: GraphExecutionTestHarness, frameNumber: Int = 0) throws -> [UInt8]
    {
        let texture = try harness.execute(graph: graph,
                                          executionInfo: harness.makeExecutionInfo(frameNumber: frameNumber),
                                          drawScene: true)
        return try pixels(of: texture, harness)
    }

    private func pixels(of texture: MTLTexture, _ harness: GraphExecutionTestHarness) throws -> [UInt8]
    {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat,
                                                                  width: texture.width,
                                                                  height: texture.height,
                                                                  mipmapped: false)
        descriptor.storageMode = .shared
        guard let readback = harness.context.device.makeTexture(descriptor: descriptor),
              let commandBuffer = harness.renderer.commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else { throw GraphExecutionTestFailure("Failed to make the readback texture") }
        blit.copy(from: texture, to: readback)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            if let baseAddress = buffer.baseAddress
            {
                readback.getBytes(baseAddress, bytesPerRow: texture.width * 4,
                                  from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            }
        }
        return bytes
    }

    @Test("Each iteration draws the points it published, not the last iteration's")
    func eachIterationDrawsItsOwnPoints() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let iterated = makeIteratorGraph(harness)
        let reference = makeReferenceGraph(harness, offsets: Self.offsets)
        let empty = makeReferenceGraph(harness, offsets: [])
        for graph in [iterated, reference, empty] { try harness.graphRenderer(for: graph).startExecution() }
        defer { for graph in [iterated, reference, empty] { try? harness.graphRenderer(for: graph).stopExecution() } }

        // Several frames, so frames that reuse heap memory still draw their own points.
        var iteratedPixels: [UInt8] = []
        for frameNumber in 0 ..< 3 { iteratedPixels = try render(iterated, harness, frameNumber: frameNumber) }
        let referencePixels = try render(reference, harness)

        #expect(referencePixels != (try render(empty, harness)), "the reference draws its squares")
        #expect(iteratedPixels == referencePixels, "two iterations draw both squares, not the last one twice")
    }

    @Test("An Iterator of points inside Render to Image draws every iteration into its target")
    func iteratorOfPointsInsideRenderToImage() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let imageNode = DeferredSubgraphNode(context: harness.context, subGraph: makeIteratorGraph(harness))
        imageNode.inputWidth.value = 64
        imageNode.inputHeight.value = 64
        let outer = Graph(context: harness.context)
        outer.addNode(imageNode)
        let reference = makeReferenceGraph(harness, offsets: Self.offsets)
        for graph in [outer, reference] { try harness.graphRenderer(for: graph).startExecution() }
        defer { for graph in [outer, reference] { try? harness.graphRenderer(for: graph).stopExecution() } }

        try harness.render(graph: outer, executionInfo: harness.makeExecutionInfo())
        let image = try #require(imageNode.outputColorTexture.value)
        #expect(try pixels(of: image.texture, harness) == render(reference, harness))
    }
}
