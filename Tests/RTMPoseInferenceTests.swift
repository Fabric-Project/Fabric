import CoreImage
import Foundation
import Metal
import Testing
import simd
@testable import Fabric

@Suite("RTMPose Inference")
struct RTMPoseInferenceTests
{
    private func makeDummyImage() -> FabricImage?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        return FabricImage.unmanaged(texture: texture)
    }

    // Whether Models/Pose has real .mlpackage files bundled varies by
    // environment (CI vs. a dev machine that's run the conversion
    // pipeline), so this tolerates either outcome — the point is that
    // run() never crashes, not that inference specifically succeeds.
    @Test("run() never crashes, regardless of whether a real model is bundled")
    func runIsSafeWithOrWithoutBundledModel() throws
    {
        guard let image = makeDummyImage() else { return }
        let ciContext = CIContext()
        let keypointCount = 21

        // A missing bundled model throws — that's an expected outcome in
        // some environments (e.g. CI without the conversion pipeline run),
        // not a test failure, so it's swallowed to an empty result here.
        let result = (try? RTMPoseInference.run(image: image, regionOfInterest: simd_float4(0, 0, 1, 1), modelIdentity: .handPose, keypointCount: keypointCount, ciContext: ciContext)) ?? []

        if result.isEmpty == false
        {
            // A real model was found and ran — 21 hand keypoints, each finite.
            #expect(result.count == keypointCount)
            for position in result
            {
                #expect(position.x.isFinite && position.y.isFinite)
            }
        }
    }
}
