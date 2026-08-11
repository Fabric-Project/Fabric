import Foundation
import Metal
import simd
import Testing
@testable import Fabric
import Satin

@Suite("Hand Pose Analysis Node")
struct HandPoseAnalysisNodeTests
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

    @Test("Finger outputs are ordered Vector 2 arrays")
    func fingerOutputContract() throws
    {
        guard let context = makeContext() else { return }
        let node = HandPoseAnalysisNode(context: context)

        let fingerPortNames = ["outputThumb", "outputIndex", "outputMiddle", "outputRing", "outputLittle"]
        for portName in fingerPortNames
        {
            let port: Fabric.Port = try #require(node.findPort(named: portName) as Fabric.Port?)
            #expect(port.kind == .Outlet)
            #expect(port.portType == .Array(portType: .Vector2))
        }

        #expect(node.outputPorts().map(\.name) == ["Thumb", "Index", "Middle", "Ring", "Little", "Wrist"])
        #expect(node.outputWrist.portType == .Vector2)
        #expect(node.findPort(named: "outputThumb1") as Fabric.Port? == nil)
    }

    @Test("Finger array ports survive serialization")
    func fingerOutputsSurviveSerialization() throws
    {
        guard let context = makeContext() else { return }
        let original = HandPoseAnalysisNode(context: context)
        let encoded = try JSONEncoder().encode(original)

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(HandPoseAnalysisNode.self, from: encoded)

        #expect(decoded.outputThumb.portType == .Array(portType: .Vector2))
        #expect(decoded.outputIndex.portType == .Array(portType: .Vector2))
        #expect(decoded.outputMiddle.portType == .Array(portType: .Vector2))
        #expect(decoded.outputRing.portType == .Array(portType: .Vector2))
        #expect(decoded.outputLittle.portType == .Array(portType: .Vector2))
        #expect(decoded.outputWrist.portType == .Vector2)
    }
}
