import Foundation
import Metal
import Satin
import Testing
@testable import Fabric

@Suite("LUT Processor Node")
struct LUTProcessorNodeTests
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

    private func makeLUTFile() throws -> URL
    {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).cube")
        let contents = """
        LUT_3D_SIZE 2
        0 0 0
        0 0 1
        0 1 0
        0 1 1
        1 0 0
        1 0 1
        1 1 0
        1 1 1
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("File initializer stores the LUT path and missing files do not prevent deserialization")
    func filePathSurvivesRoundTripAndReloads() throws
    {
        guard let context = makeContext() else { return }

        let lutURL = try makeLUTFile()
        defer { try? FileManager.default.removeItem(at: lutURL) }

        let node = try LUTProcessorNode(context: context, fileURL: lutURL)
        #expect(node.inputFilePathParam.value == lutURL.standardizedFileURL.absoluteString)
        #expect(node.imageInputPorts().count == 1)

        let encodedNode = try JSONEncoder().encode(node)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decodedNode = try decoder.decode(LUTProcessorNode.self, from: encodedNode)

        #expect(decodedNode.inputFilePathParam.value == lutURL.standardizedFileURL.absoluteString)
        #expect(decodedNode.inputFilePathParam.valueDidChange)
        #expect(decodedNode.imageInputPorts().count == 1)

        try FileManager.default.removeItem(at: lutURL)
        let decodedMissingLUTNode = try decoder.decode(LUTProcessorNode.self, from: encodedNode)
        #expect(decodedMissingLUTNode.inputFilePathParam.value == lutURL.standardizedFileURL.absoluteString)
        #expect(decodedMissingLUTNode.inputFilePathParam.valueDidChange)
        #expect(decodedMissingLUTNode.imageInputPorts().count == 1)
    }
}
