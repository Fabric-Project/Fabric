import Foundation
import Metal
import simd
import Testing
@testable import Fabric
import Satin

/// Temporary probe for the 3b Transforms sample: reports what each transform node outputs after a few frames.
@Suite("3b Transforms probe", .serialized)
struct TransformsSampleProbeTests
{
    @Test("Every transform node in 3b outputs a finite value")
    func transformChainOutputs() throws
    {
        let documentURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Fabric-Samples/Samples/3 - 3D Scenes and Transforms/3b - Transforms.fabric")
        guard FileManager.default.fileExists(atPath: documentURL.path) else { return }

        let harness = try #require(GraphExecutionTestHarness())
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context,
                                         fileReferenceBaseURL: documentURL.deletingLastPathComponent())
        let graph = try decoder.decode(Graph.self, from: Data(contentsOf: documentURL))

        try harness.graphRenderer(for: graph).startExecution()
        for frameNumber in 0..<4
        {
            try harness.execute(graph, frameNumber: frameNumber)
        }

        for node in graph.nodes where node is PassThroughNode<simd_float4x4>
            || node is RotateTransformNode || node is TranslateTransformNode || node is DecomposeTransformNode
            || node is MeshNode
        {
            print("[3b probe] \(node.debugDescription) [\(node.executionState)]")
            for port in node.inputPorts() + node.outputPorts()
            {
                print("[3b probe]     \(port.kind) \(port.name) connected=\(!port.connections.isEmpty) value=\(String(describing: port.snapshotValue()))")
            }
            for port in node.outputPorts()
            {
                if let transformPort = port as? NodePort<simd_float4x4>
                {
                    let value = try #require(transformPort.value, "\(node.debugDescription) sent no \(port.name)")
                    #expect(value != simd_float4x4(), "\(node.debugDescription) sent a zero \(port.name)")
                }
            }
        }
    }
}
