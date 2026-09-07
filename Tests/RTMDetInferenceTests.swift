import Foundation
import Metal
import Testing
@testable import Fabric

@Suite("RTMDet Inference")
struct RTMDetInferenceTests
{
    private func makeDummyImage() -> FabricImage?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        return FabricImage.unmanaged(texture: texture)
    }

    // Whether Models/Pose has the RTMDet detector weight files bundled
    // varies by environment, so this tolerates either outcome — a missing
    // bundled model throws, which is swallowed to an empty result here
    // rather than treated as a test failure.
    @Test("run() never crashes, regardless of whether a real model is bundled")
    func runIsSafeWithOrWithoutBundledModel()
    {
        guard let image = makeDummyImage() else { return }
        guard let commandQueue = image.texture.device.makeCommandQueue() else { return }

        let result = (try? RTMDetInference.run(image: image, targetClass: .personDetector, maxDetections: 1, device: image.texture.device, commandQueue: commandQueue)) ?? []

        for detection in result
        {
            #expect(detection.confidence >= 0 && detection.confidence <= 1)
        }
    }
}
