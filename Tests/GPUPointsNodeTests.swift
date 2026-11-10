import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

/// The GPU points nodes: each compiles its kernel on first use, then publishes.
@Suite("GPU points nodes")
struct GPUPointsNodeTests
{
    /// Enables `node`, which compiles its kernel, runs it once, committing the frame, and returns
    /// what it published.
    private func executeUntilPublished(_ node: BaseGPUPointsNode, _ harness: GraphExecutionTestHarness) throws -> Satin.Points?
    {
        try node.enableExecution(renderer: harness.renderer)
        let commandBuffer = try #require(harness.renderer.commandQueue.makeCommandBuffer())
        try node.execute(renderer: harness.renderer, executionInfo: harness.makeExecutionInfo(frameNumber: 0),
                         renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return node.outputPoints.value
    }

    /// A shared copy of a published attribute's first `count` elements.
    private func readBack<Element>(_ attribute: PublishedAttribute, count: Int, as _: Element.Type,
                                   _ harness: GraphExecutionTestHarness) throws -> [Element]
    {
        let length = count * attribute.layout.byteStride
        let shared = try #require(harness.context.device.makeBuffer(length: length, options: .storageModeShared))
        let commandBuffer = try #require(harness.renderer.commandQueue.makeCommandBuffer())
        let blit = try #require(commandBuffer.makeBlitCommandEncoder())
        blit.copy(from: attribute.buffer, sourceOffset: attribute.layout.byteOffset, to: shared, destinationOffset: 0, size: length)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let elements = shared.contents().bindMemory(to: Element.self, capacity: count)
        return Array(UnsafeBufferPointer(start: elements, count: count))
    }

    @Test("Transform Points moves positions and shares every other attribute")
    func transformMovesPositions() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let allocator = harness.context.gpuAllocator
        let color = try PublishedAttribute.publishing(ContiguousArray<simd_float4>([[1, 0, 0, 1], [0, 1, 0, 1]]),
                                                      scalar: .float32, components: 4, allocator: allocator)
        let positions: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 2, 3]]
        let input = try Satin.Points(attributes: [
            (.position, try PublishedAttribute.publishing(positions, scalar: .float32, components: 3, allocator: allocator)),
            (.color, color),
        ], topology: .implicit, bounds: .of(positions))

        let node = TransformPointsNode(context: harness.context)
        node.inputPoints.value = input
        node.inputTransform.value = simd_float4x4(translation: [1, 0, 0])
        let moved = try #require(try executeUntilPublished(node, harness))

        let movedPositions = try readBack(moved.position, count: 2, as: simd_float4.self, harness)
        #expect(simd_make_float3(movedPositions[0]) == simd_float3(1, 0, 0))
        #expect(simd_make_float3(movedPositions[1]) == simd_float3(2, 2, 3))
        #expect(moved.attribute(.color) === color)
        guard case let .known(bounds) = moved.bounds else
        {
            Issue.record("Known bounds stay known")
            return
        }
        #expect(bounds.min.x == 1 && bounds.max.x == 2)
    }

    @Test("Points from Image makes one colored point per step")
    func pointsFromImage() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let image = try harness.makeImage(width: 4, height: 4)
        let clear = MTLRenderPassDescriptor()
        clear.colorAttachments[0].texture = image.texture
        clear.colorAttachments[0].loadAction = .clear
        clear.colorAttachments[0].storeAction = .store
        clear.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 1)
        let commandBuffer = try #require(harness.renderer.commandQueue.makeCommandBuffer())
        try #require(commandBuffer.makeRenderCommandEncoder(descriptor: clear)).endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let node = PointsFromImageNode(context: harness.context)
        node.inputImage.value = image
        node.inputStep.value = 2
        let points = try #require(try executeUntilPublished(node, harness))

        #expect(points.count == 4)
        let colors = try readBack(try #require(points.attribute(.color)), count: 4, as: simd_float4.self, harness)
        #expect(colors.allSatisfy { simd_distance($0, [1, 0, 0, 1]) < 0.01 })
        let positions = try readBack(points.position, count: 4, as: simd_float4.self, harness)
        #expect(positions.allSatisfy { abs($0.x) <= 1 && abs($0.y) <= 1 && $0.z == 0 })
    }

    @Test("Points Compute writes the attributes its settings turn on, and its points draw")
    func pointsComputeWritesAndDraws() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let node = PointsComputeNode(context: harness.context)
        node.inputCount.value = 1_000
        let points = try #require(try executeUntilPublished(node, harness))
        #expect(points.count == 1_000)
        #expect(points.slots.map { $0.index } == [.Position, .Color, .PointSize])
        if case .known = points.bounds { Issue.record("GPU-written points have unknown bounds") }

        // Acceptance: Points Compute → Points Geometry → Mesh + Basic Color draws.
        let graph = Graph(context: harness.context)
        let compute = PointsComputeNode(context: harness.context)
        compute.inputCount.value = 100_000
        let geometry = PointsGeometryNode(context: harness.context)
        let material = BasicColorMaterialNode(context: harness.context)
        let mesh = MeshNode(context: harness.context)
        for graphNode in [compute, geometry, material, mesh] as [Node] { graph.addNode(graphNode) }
        graph.connect(compute.outputPoints, to: geometry.inputPoints)
        graph.connect(geometry.outputGeometry, to: mesh.inputGeometry)
        graph.connect(material.outputMaterial, to: mesh.inputMaterial)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }

        var drewPoints = false
        for frameNumber in 0 ..< 10 where !drewPoints
        {
            let texture = try harness.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: frameNumber), drawScene: true)
            let lit = try hasLitPixels(texture, harness)
            drewPoints = compute.outputPoints.value != nil && lit
        }
        #expect(drewPoints)
    }

    @Test("A function that doesn't compile is the node's status, and publishes nothing")
    func failingFunctionIsTheStatus() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let node = PointsComputeNode(context: harness.context, settings: PointsComputeSettings(
            hasNormals: false, hasColors: false, hasSizes: false, hasTexcoords: false, customAttributes: [], streamInputs: [], countSource: "",
            kernelSource: "void pointsCompute(uint id, constant PointsComputeUniforms &uniforms, thread const PointsComputeInputs &inputs, thread PointsComputeOutput &point) { point.nope = 1; }"))
        #expect(try executeUntilPublished(node, harness) == nil)
        if case .error = node.status {} else { Issue.record("The compile error is the node's status") }
    }

    @Test("Custom attribute names that aren't shader fields are dropped")
    func computeCustomNamesAreIdentifiers()
    {
        let settings = PointsComputeSettings(hasNormals: false, hasColors: false, hasSizes: false, hasTexcoords: false,
                                             customAttributes: [PointsCustomAttribute(name: "two words", components: 1),
                                                                PointsCustomAttribute(name: "1st", components: 1),
                                                                PointsCustomAttribute(name: "color", components: 4),
                                                                PointsCustomAttribute(name: "heat_2", components: 2)],
                                             streamInputs: [], countSource: "", kernelSource: "").normalized()
        #expect(settings.customAttributes == [PointsCustomAttribute(name: "heat_2", components: 2)])
    }

    @Test("Points a GPU pass wrote stroke on the GPU and draw, with no readback")
    func gpuPointsStrokeAndDraw() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let graph = Graph(context: harness.context)
        let compute = PointsComputeNode(context: harness.context)
        compute.inputCount.value = 64
        let stroke = PointsToLineGeometryNode(context: harness.context)
        stroke.inputWidth.value = 0.05
        let material = BasicColorMaterialNode(context: harness.context)
        let mesh = MeshNode(context: harness.context)
        mesh.inputCullingMode.value = "None"
        for graphNode in [compute, stroke, material, mesh] as [Node] { graph.addNode(graphNode) }
        graph.connect(compute.outputPoints, to: stroke.inputPoints)
        graph.connect(stroke.outputGeometry, to: mesh.inputGeometry)
        graph.connect(material.outputMaterial, to: mesh.inputMaterial)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }

        var drew = false
        for frameNumber in 0 ..< 10 where !drew
        {
            let texture = try harness.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: frameNumber), drawScene: true)
            let lit = try hasLitPixels(texture, harness)
            drew = stroke.outputGeometry.value != nil && lit
        }
        #expect(drew)
        #expect(stroke.status == nil)
    }

    private func hasLitPixels(_ texture: MTLTexture, _ harness: GraphExecutionTestHarness) throws -> Bool
    {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: texture.width,
                                                                  height: texture.height, mipmapped: false)
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
        let background = Array(bytes[0 ..< 4])
        return stride(from: 0, to: bytes.count, by: 4).contains { Array(bytes[$0 ..< $0 + 4]) != background }
    }
}
