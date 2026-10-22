import Testing
import Metal
@testable import Fabric

@Suite("Published render-target images")
struct GraphImageCopyTests {
    @Test("A published image is distinct from a subsequently overwritten target")
    func targetCopiesKeepTheirContents() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .renderTarget]
        let target = try #require(harness.context.device.makeTexture(descriptor: descriptor))
        let red: [UInt8] = [255, 0, 0, 255]
        red.withUnsafeBytes { bytes in
            if let address = bytes.baseAddress {
                target.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: address, bytesPerRow: 4)
            }
        }
        let commands = try #require(harness.renderer.makeCommandBuffer())
        let first = try harness.renderer.newImage(copying: target, commandBuffer: commands)
        let overwrite = try #require(commands.makeRenderCommandEncoder(descriptor: {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1)
            return pass
        }()))
        overwrite.endEncoding()
        let second = try harness.renderer.newImage(copying: target, commandBuffer: commands)
        #expect(first.texture !== target && second.texture !== target && first.texture !== second.texture)
        let readback = try #require(harness.context.device.makeBuffer(length: 512, options: .storageModeShared))
        let blit = try #require(commands.makeBlitCommandEncoder())
        for (index, image) in [first, second].enumerated() {
            blit.copy(from: image.texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(), sourceSize: .init(width: 1, height: 1, depth: 1), to: readback, destinationOffset: index * 256, destinationBytesPerRow: 256, destinationBytesPerImage: 256)
        }
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)
        #expect(readback.contents().load(as: UInt8.self) == 255)
        #expect(readback.contents().advanced(by: 256 + 2).load(as: UInt8.self) == 255)
    }
}
