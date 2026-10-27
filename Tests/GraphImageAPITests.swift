import Testing
import Metal
import Satin
import Fabric

@Suite("Graph image public API", .serialized)
struct GraphImageAPITests {
    private func renderer() throws -> GraphRenderer {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        return GraphRenderer(context: context, graph: Graph(context: context))
    }

    private func clear(_ texture: MTLTexture, to color: MTLClearColor,
                       using commands: MTLCommandBuffer) throws {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = color
        let encoder = try #require(commands.makeRenderCommandEncoder(descriptor: pass))
        encoder.endEncoding()
    }

    private func finish(_ commands: MTLCommandBuffer) throws {
        commands.commit()
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)
        if let error = commands.error { throw error }
    }

    // These pixel tests request RGBA8 explicitly, so a single pixel is four bytes.
    private func firstPixel(_ texture: MTLTexture, using renderer: GraphRenderer) throws -> [UInt8] {
        let commands = try #require(renderer.makeCommandBuffer())
        let readback = try #require(renderer.device.makeBuffer(length: 256, options: .storageModeShared))
        let blit = try #require(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: .init(), sourceSize: .init(width: 1, height: 1, depth: 1),
                  to: readback, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256)
        blit.endEncoding()
        try finish(commands)
        return Array(UnsafeBufferPointer(start: readback.contents().assumingMemoryBound(to: UInt8.self), count: 4))
    }

    @Test("An image uses the requested size and renderer's default format")
    func defaultFormat() throws {
        let renderer = try renderer()
        let image = try renderer.newImage(withWidth: 17, height: 9)
        #expect(image.texture.width == 17)
        #expect(image.texture.height == 9)
        #expect(image.texture.pixelFormat == renderer.colorPixelFormat)
        #expect(image.texture.mipmapLevelCount == 1)
    }

    @Test("Callers can choose an image format", arguments: [MTLPixelFormat.r8Unorm, .rgba8Unorm, .rgba16Float])
    func explicitFormat(format: MTLPixelFormat) throws {
        let renderer = try renderer()
        let image = try renderer.newImage(withWidth: 17, height: 9, format: format)
        #expect(image.texture.width == 17)
        #expect(image.texture.height == 9)
        #expect(image.texture.pixelFormat == format)
    }

    @Test("Mipmaps are allocated only when requested", arguments: [false, true])
    func mipmaps(enabled: Bool) throws {
        let renderer = try renderer()
        let image = try renderer.newImage(withWidth: 64, height: 32, format: .rgba8Unorm, mipmapped: enabled)
        #expect(image.texture.width == 64)
        #expect(image.texture.height == 32)
        #expect(image.texture.mipmapLevelCount == (enabled ? 7 : 1))
    }

    @Test("Keeping an image keeps its contents while other images are created")
    func retainedImageKeepsContents() throws {
        let renderer = try renderer()
        let original = try renderer.newImage(withWidth: 4, height: 4, format: .rgba8Unorm)
        let commands = try #require(renderer.makeCommandBuffer())
        try clear(original.texture, to: MTLClearColorMake(1, 0, 0, 1), using: commands)
        for size in [4, 17, 128, 512, 4] {
            let other = try renderer.newImage(withWidth: size, height: size, format: .rgba8Unorm)
            try clear(other.texture, to: MTLClearColorMake(0, 0, 1, 1), using: commands)
        }
        try finish(commands)
        #expect(try firstPixel(original.texture, using: renderer) == [255, 0, 0, 255])
    }

    @Test("Keeping only a texture is enough to preserve it after its image is released")
    func retainedTextureKeepsContents() throws {
        let renderer = try renderer()
        var image: FabricImage? = try renderer.newImage(withWidth: 4, height: 4, format: .rgba8Unorm)
        let texture = try #require(image).texture
        let commands = try #require(renderer.makeCommandBuffer())
        try clear(texture, to: MTLClearColorMake(1, 0, 0, 1), using: commands)
        image = nil
        for _ in 0..<48 {
            let other = try renderer.newImage(withWidth: 4, height: 4, format: .rgba8Unorm)
            try clear(other.texture, to: MTLClearColorMake(0, 0, 1, 1), using: commands)
        }
        try finish(commands)
        #expect(try firstPixel(texture, using: renderer) == [255, 0, 0, 255])
    }

    @Test("Another renderer can copy an image without keeping a live link to its contents")
    func copiedImageIsIndependent() throws {
        let producer = try renderer()
        let source = try producer.newImage(withWidth: 4, height: 4, format: .rgba8Unorm)
        let create = try #require(producer.makeCommandBuffer())
        try clear(source.texture, to: MTLClearColorMake(1, 0, 0, 1), using: create)
        try finish(create)

        let consumer = try renderer()
        let commands = try #require(consumer.makeCommandBuffer())
        let copy = try consumer.newImage(copying: source.texture, commandBuffer: commands)
        try clear(source.texture, to: MTLClearColorMake(0, 0, 1, 1), using: commands)
        try finish(commands)
        #expect(try firstPixel(copy.texture, using: consumer) == [255, 0, 0, 255])
        #expect(try firstPixel(source.texture, using: producer) == [0, 0, 255, 255])
    }
}
