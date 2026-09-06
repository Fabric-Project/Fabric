import Foundation
import Metal
import simd
import Testing
@testable import Fabric
import Satin

@Suite("Body Pose Detection Node")
struct BodyPoseDetectionNodeTests
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

    @Test("Generic keypoints output plus grouped convenience outputs, no instance-count port")
    func portContract() throws
    {
        guard let context = makeContext() else { return }
        let node = BodyPoseDetectionNode(context: context)

        #expect(node.outputPorts().map(\.name) == [
            "Keypoints", "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
        ])

        let keypointsPort: Fabric.Port = try #require(node.findPort(named: "outputKeypoints") as Fabric.Port?)
        #expect(keypointsPort.portType == .Array(portType: .Vector2))

        for groupPortName in ["outputHead", "outputTorso", "outputLeftArm", "outputRightArm", "outputLeftLeg", "outputRightLeg"]
        {
            let port: Fabric.Port = try #require(node.findPort(named: groupPortName) as Fabric.Port?)
            #expect(port.portType == .Array(portType: .Vector2))
        }

        // Instance count is the upstream Region Detection node's job now.
        #expect(node.findPort(named: "inputPersonCount") as Fabric.Port? == nil)

        let roiPort: Fabric.Port = try #require(node.findPort(named: "inputRegionOfInterest") as Fabric.Port?)
        #expect(roiPort.portType == .Vector4)
    }

    @Test("Model tier defaults to Tiny")
    func modelTierDefaultsToTiny() throws
    {
        guard let context = makeContext() else { return }
        let node = BodyPoseDetectionNode(context: context)

        #expect(node.inputModelTier.value == "Tiny")
    }
}
