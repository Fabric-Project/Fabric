import Testing
import Metal
import Satin
@testable import Fabric

/// Render to Image renders depth straight into a new output image each frame instead of copying
/// its encoder's depth texture.
@Suite("Render to Image depth output", .serialized)
struct RenderToImageDepthTests {
    private func makeBoxNode(_ harness: GraphExecutionTestHarness) -> DeferredSubgraphNode {
        let deferred = DeferredSubgraphNode(context: harness.context)
        deferred.inputWidth.value = 64
        deferred.inputHeight.value = 32
        let geometry = BoxGeometryNode(context: harness.context)
        let material = BasicColorMaterialNode(context: harness.context)
        let mesh = MeshNode(context: harness.context)
        deferred.subGraph.addNode(geometry)
        deferred.subGraph.addNode(material)
        deferred.subGraph.addNode(mesh)
        deferred.subGraph.connect(geometry.outputGeometry, to: mesh.inputGeometry)
        deferred.subGraph.connect(material.outputMaterial, to: mesh.inputMaterial)
        return deferred
    }

    /// Depth values at the given pixels, read back through a shared buffer.
    private func depth(of texture: MTLTexture, at pixels: [(x: Int, y: Int)], _ harness: GraphExecutionTestHarness) throws -> [Float] {
        let bytesPerRow = texture.width * MemoryLayout<Float>.stride
        let buffer = try #require(harness.context.device.makeBuffer(length: bytesPerRow * texture.height, options: .storageModeShared))
        let commands = try #require(harness.context.commandQueue.makeCommandBuffer())
        let blit = try #require(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: bytesPerRow * texture.height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let values = buffer.contents().assumingMemoryBound(to: Float.self)
        return pixels.map { values[$0.y * texture.width + $0.x] }
    }

    @Test("Depth renders into a new heap image each frame, not the encoder's own texture")
    func depthRendersDirectly() throws {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let deferred = makeBoxNode(harness)
        deferred.outputDepthTexture.published = true
        graph.addNode(deferred)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }

        try harness.render(graph: graph, executionInfo: harness.makeExecutionContext(time: 0, deltaTime: 0, frameNumber: 0))
        let first = try #require(deferred.outputDepthTexture.value)
        try harness.render(graph: graph, executionInfo: harness.makeExecutionContext(time: 1, deltaTime: 1, frameNumber: 1))
        let second = try #require(deferred.outputDepthTexture.value)

        #expect(first.texture !== deferred.graphRenderer.renderEncoder.depthTexture)
        #expect(first.texture !== second.texture, "each frame publishes its own depth image")
        #expect(first.texture.heap != nil)
        #expect(first.texture.width == 64 && first.texture.height == 32)
        #expect(first.texture.pixelFormat == deferred.graphRenderer.renderEncoder.depthPixelFormat)

        // Satin clears to its configured depth (reversed: 0) and nearer surfaces differ from it.
        let cleared = Float(deferred.graphRenderer.renderEncoder.clearDepth)
        let values = try depth(of: second.texture, at: [(32, 16), (0, 0)], harness)
        #expect(values[0] != cleared, "the box covers the centre")
        #expect(values[1] == cleared, "the corner keeps the cleared depth")
    }

    @Test("Unused depth and deferred outputs get no image; the color output always does")
    func unusedOutputsAreSkipped() throws {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let deferred = makeBoxNode(harness)
        deferred.deferredMRTEnabled = true
        graph.addNode(deferred)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }

        try harness.render(graph: graph, executionInfo: harness.makeExecutionContext(time: 0, deltaTime: 0, frameNumber: 0))
        #expect(deferred.outputColorTexture.value != nil)
        #expect(deferred.outputDepthTexture.value == nil)
        let albedo = try #require(deferred.findPort(named: "outputAlbedoTexture", as: NodePort<FabricImage>.self))
        #expect(albedo.value == nil)

        albedo.published = true
        try harness.render(graph: graph, executionInfo: harness.makeExecutionContext(time: 1, deltaTime: 1, frameNumber: 1))
        #expect(albedo.value != nil)
        #expect(deferred.outputDepthTexture.value == nil)
    }
}
