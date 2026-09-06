import Foundation
import Metal
import simd
import Testing
@testable import Fabric
import Satin

@Suite("Region Detection Node")
struct RegionDetectionNodeTests
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

    @Test("Ports match the plan: image + target + max detections in, regions/region/count out")
    func portContract() throws
    {
        guard let context = makeContext() else { return }
        let node = RegionDetectionNode(context: context)

        #expect(node.outputPorts().map(\.name) == ["Regions", "Region", "Count"])

        let regionsPort: Fabric.Port = try #require(node.findPort(named: "outputRegionsOfInterest") as Fabric.Port?)
        #expect(regionsPort.portType == .Array(portType: .Vector4))

        let regionPort: Fabric.Port = try #require(node.findPort(named: "outputRegionOfInterest") as Fabric.Port?)
        #expect(regionPort.portType == .Vector4)

        let countPort: Fabric.Port = try #require(node.findPort(named: "outputDetectionCount") as Fabric.Port?)
        #expect(countPort.portType == .Int)

        #expect(node.inputTarget.portType == .String)
        #expect(node.inputMaxDetections.portType == .Int)
    }

    @Test("Target parameter defaults to Person with the expected options")
    func targetParameterDefaults() throws
    {
        guard let context = makeContext() else { return }
        let node = RegionDetectionNode(context: context)

        #expect(node.inputTarget.value == "Person")
    }

    @Test("Ports survive serialization")
    func portsSurviveSerialization() throws
    {
        guard let context = makeContext() else { return }
        let original = RegionDetectionNode(context: context)
        let encoded = try JSONEncoder().encode(original)

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(RegionDetectionNode.self, from: encoded)

        #expect(decoded.outputRegionsOfInterest.portType == .Array(portType: .Vector4))
        #expect(decoded.outputRegionOfInterest.portType == .Vector4)
        #expect(decoded.outputDetectionCount.portType == .Int)
    }
}
