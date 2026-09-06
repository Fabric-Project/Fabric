import Metal
import Testing
import simd
@testable import Fabric

@Suite("RTMPose Metal Input Preprocessor")
struct RTMPoseInputPreprocessorTests
{
    @Test("Crops a bottom-left ROI and writes normalized planar RGB")
    func cropsAndNormalizesOnGPU() throws
    {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else { return }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 2,
            height: 2,
            mipmapped: false
        )
        textureDescriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return }

        // Stored rows are top-left, top-right, bottom-left, bottom-right.
        let pixels: [UInt8] = [
            0, 0, 255, 255,     0, 255, 0, 255,
            255, 0, 0, 255,     255, 255, 255, 255,
        ]
        texture.replace(
            region: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: 8
        )

        let preprocessor = try RTMPoseInputPreprocessor(
            device: device,
            outputWidth: 1,
            outputHeight: 1
        )
        let privateOutput = try preprocessor.encode(
            image: FabricImage.unmanaged(texture: texture),
            regionOfInterest: simd_float4(0, 0, 0.5, 0.5),
            commandQueue: commandQueue
        )

        guard let readableOutput = device.makeBuffer(
            length: 3 * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ),
        let commandBuffer = commandQueue.makeCommandBuffer(),
        let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }

        blitEncoder.copy(
            from: privateOutput,
            sourceOffset: 0,
            to: readableOutput,
            destinationOffset: 0,
            size: readableOutput.length
        )
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let values = readableOutput.contents().bindMemory(to: Float.self, capacity: 3)
        // Bottom-left is blue in BGRA storage, so semantic RGB is (0, 0, 255).
        #expect(abs(values[0] - ((0 - 123.675) / 58.395)) < 0.001)
        #expect(abs(values[1] - ((0 - 116.28) / 57.12)) < 0.001)
        #expect(abs(values[2] - ((255 - 103.53) / 57.375)) < 0.001)
    }
}
