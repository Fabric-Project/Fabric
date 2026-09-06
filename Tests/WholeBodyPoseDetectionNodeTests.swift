import Foundation
import Metal
import simd
import Testing
@testable import Fabric
import Satin

@Suite("Whole-Body Pose Detection Node")
struct WholeBodyPoseDetectionNodeTests
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

    @Test("Generic 133-keypoint output plus grouped convenience outputs including hands and feet")
    func portContract() throws
    {
        guard let context = makeContext() else { return }
        let node = WholeBodyPoseDetectionNode(context: context)

        #expect(node.outputPorts().map(\.name) == [
            "Keypoints", "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
            "Left Foot", "Right Foot", "Face", "Left Hand", "Right Hand",
        ])

        for groupPortName in [
            "outputKeypoints", "outputHead", "outputTorso", "outputLeftArm", "outputRightArm",
            "outputLeftLeg", "outputRightLeg", "outputLeftFoot", "outputRightFoot",
            "outputFace", "outputLeftHand", "outputRightHand",
        ]
        {
            let port: Fabric.Port = try #require(node.findPort(named: groupPortName) as Fabric.Port?)
            #expect(port.portType == .Array(portType: .Vector2))
        }
    }

    @Test("Model tier defaults to Medium, the only published tier")
    func modelTierDefaultsToMedium() throws
    {
        guard let context = makeContext() else { return }
        let node = WholeBodyPoseDetectionNode(context: context)

        #expect(node.inputModelTier.value == "Medium")
    }
}
