import Foundation
import Metal
import simd
import Testing
@testable import Fabric
import Satin

@Suite("Face Pose Analysis Node")
struct FacePoseAnalysisNodeTests
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

    @Test("Pre-existing region outputs are unchanged Vector 2 arrays")
    func regionOutputContract() throws
    {
        guard let context = makeContext() else { return }
        let node = FacePoseAnalysisNode(context: context)

        let regionPortNames = [
            "outputFaceContour", "outputLeftEye", "outputRightEye",
            "outputLeftPupil", "outputRightPupil",
            "outputLeftEyebrow", "outputRightEyebrow",
            "outputNose", "outputNoseCrest", "outputMedianLine",
            "outputInnerLips", "outputOuterLips",
        ]

        for portName in regionPortNames
        {
            let port: Fabric.Port = try #require(node.findPort(named: portName) as Fabric.Port?)
            #expect(port.kind == .Outlet)
            #expect(port.portType == .Array(portType: .Vector2))
        }

        #expect(node.outputPorts().map(\.name) == [
            "Face Contour", "Left Eye", "Right Eye", "Left Pupil", "Right Pupil",
            "Left Eyebrow", "Right Eyebrow", "Nose", "Nose Crest", "Median Line",
            "Inner Lips", "Outer Lips",
        ])
    }

    @Test("Additive Region of Interest inlet exists, is a Vector 4, and doesn't disturb existing outputs")
    func regionOfInterestInletIsAdditive() throws
    {
        guard let context = makeContext() else { return }
        let node = FacePoseAnalysisNode(context: context)

        let roiPort: Fabric.Port = try #require(node.findPort(named: "inputRegionOfInterest") as Fabric.Port?)
        #expect(roiPort.kind == .Inlet)
        #expect(roiPort.portType == .Vector4)
        #expect(node.inputRegionOfInterest.value == nil, "Unconnected ROI has no value — nodes fall back to full-frame (0,0,1,1) at read time, not via a port default")
    }

    @Test("Region outputs survive serialization")
    func regionOutputsSurviveSerialization() throws
    {
        guard let context = makeContext() else { return }
        let original = FacePoseAnalysisNode(context: context)
        let encoded = try JSONEncoder().encode(original)

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(FacePoseAnalysisNode.self, from: encoded)

        #expect(decoded.outputFaceContour.portType == .Array(portType: .Vector2))
        #expect(decoded.outputLeftPupil.portType == .Array(portType: .Vector2))
        #expect(decoded.inputRegionOfInterest.portType == .Vector4)
    }
}
