import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

/// A material's Point Sprite setting: what it does to points, and that it leaves triangles alone.
@Suite("Material point sprites", .serialized)
struct PointSpriteTests
{
    /// The pixels lit by one 40-pixel point, or by a plane when `plane` is set, drawn with a Color
    /// Material whose point sprite is `sprite`; `image` goes to its Point Sprite Image input.
    private func litPixels(sprite: MaterialPointSprite, image: FabricImage? = nil, plane: Bool = false,
                           harness: GraphExecutionTestHarness) throws -> Int
    {
        let graph = Graph(context: harness.context)
        let material = BasicColorMaterialNode(context: harness.context, settings: MaterialSettings(pointSprite: sprite))
        try #require(material.inputPointSize).value = 40
        if let image
        {
            let imagePort: NodePort<FabricImage>? = material.findPort(named: "inputPointSpriteImage")
            #expect(imagePort != nil, "Image adds the Point Sprite Image input")
            imagePort?.value = image
        }
        let mesh = MeshNode(context: harness.context)
        mesh.inputCullingMode.value = "None"
        graph.addNode(material)
        graph.addNode(mesh)
        graph.connect(material.outputMaterial, to: mesh.inputMaterial)

        if plane
        {
            let planeNode = PlaneGeometryNode(context: harness.context)
            graph.addNode(planeNode)
            graph.connect(planeNode.outputGeometry, to: mesh.inputGeometry)
        }
        else
        {
            let points = PointsGeometryNode(context: harness.context)
            points.inputPrimitiveType.value = "Point"
            points.inputPoints.value = try Satin.Points(positions: [[0, 0, 0]], allocator: harness.context.gpuAllocator)
            graph.addNode(points)
            graph.connect(points.outputGeometry, to: mesh.inputGeometry)
        }

        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }
        let texture = try harness.execute(graph: graph, executionInfo: harness.makeExecutionInfo(), drawScene: true)
        return try lit(texture, harness)
    }

    @Test("A disc draws a round point, about π/4 of the square one")
    func discRoundsPoints() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 128, renderHeight: 128) else { return }
        let square = try litPixels(sprite: .square, harness: harness)
        let disc = try litPixels(sprite: .disc, harness: harness)
        #expect(square > 0 && disc > 0)
        let ratio = Double(disc) / Double(square)
        #expect(ratio > 0.65 && ratio < 0.9, "disc \(disc) of square \(square)")
    }

    @Test("An image sprite shows its image: a transparent one draws nothing")
    func imageSpriteSamples() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 128, renderHeight: 128) else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: 4, height: 4, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = try #require(harness.context.device.makeTexture(descriptor: descriptor))
        let transparent = [simd_float4](repeating: .zero, count: 16)
        transparent.withUnsafeBytes { bytes in
            if let address = bytes.baseAddress
            {
                texture.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0, withBytes: address, bytesPerRow: 4 * MemoryLayout<simd_float4>.stride)
            }
        }
        #expect(try litPixels(sprite: .image, image: .unmanaged(texture: texture), harness: harness) == 0)
    }

    @Test("A point sprite leaves meshes of triangles as they were")
    func trianglesUnaffected() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 128, renderHeight: 128) else { return }
        let square = try litPixels(sprite: .square, plane: true, harness: harness)
        #expect(square > 0)
        #expect(try litPixels(sprite: .disc, plane: true, harness: harness) == square)
    }

    @Test("Each point sprite adds only its own input")
    func spriteInputs()
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 16, renderHeight: 16) else { return }
        let material = BasicColorMaterialNode(context: harness.context)
        #expect((material.findPort(named: "inputPointSize") as Fabric.Port?) == nil)
        #expect((material.findPort(named: "inputPointSpriteSoftness") as Fabric.Port?) == nil)
        #expect((material.findPort(named: "inputPointSpriteImage") as Fabric.Port?) == nil)
        material.setSettings(MaterialSettings(pointSprite: .disc))
        #expect((material.findPort(named: "inputPointSpriteSoftness") as Fabric.Port?) != nil)
        #expect((material.findPort(named: "inputPointSpriteImage") as Fabric.Port?) == nil)
        material.setSettings(MaterialSettings(pointSprite: .image))
        #expect((material.findPort(named: "inputPointSpriteSoftness") as Fabric.Port?) == nil)
        #expect((material.findPort(named: "inputPointSpriteImage") as Fabric.Port?) != nil)
    }

    @Test("Sprite size survives mode changes and resets when disabled")
    func sizeLifecycle() throws
    {
        let harness = try #require(GraphExecutionTestHarness(renderWidth: 16, renderHeight: 16))
        let material = BasicColorMaterialNode(context: harness.context)
        #expect(material.pointSprite == .none)
        #expect(MaterialPointSprite.allCases.first == MaterialPointSprite.none)
        material.setSettings(MaterialSettings(pointSprite: .square))
        let size = try #require(material.inputPointSize)
        size.value = 24
        _ = material.evaluate(material: material.material, atTime: 0)
        #expect(material.material.pointSize == 24)
        for mode in [MaterialPointSprite.disc, .image]
        {
            material.setSettings(MaterialSettings(pointSprite: mode))
            #expect(material.inputPointSize === size)
            #expect(material.ports.filter { $0.kind == .Inlet }.suffix(2).first === size)
        }

        let graph = Graph(context: harness.context)
        graph.addNode(material)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context)
        let reopened = try decoder.decode(Graph.self, from: JSONEncoder().encode(graph))
        let restored = try #require(reopened.node(forID: material.id) as? BasicColorMaterialNode)
        #expect(restored.pointSprite == .image)
        #expect(restored.inputPointSize?.id == size.id)
        #expect(restored.inputPointSize?.value == 24)

        material.setSettings(MaterialSettings(pointSprite: .none))
        #expect(material.inputPointSize == nil)
        #expect((material.findPort(named: "inputPointSpriteImage") as Fabric.Port?) == nil)
        _ = material.evaluate(material: material.material, atTime: 0)
        #expect(material.material.pointSize == 1)
        #expect(material.material.pointSprite == .square)
    }

    /// How many pixels differ from the corner pixel, the background.
    private func lit(_ texture: MTLTexture, _ harness: GraphExecutionTestHarness) throws -> Int
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
        return stride(from: 0, to: bytes.count, by: 4).filter { Array(bytes[$0 ..< $0 + 4]) != background }.count
    }
}
