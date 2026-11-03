import Foundation
import Metal
import Satin
import XCTest
@testable import Fabric

/// Runs with the rest of the tests. See GraphBenchmark for where results go and how to get real numbers.
final class GraphPerformanceBenchmark: XCTestCase
{
    private static let repositoryRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The sample at `path` under Fabric-Samples/Samples and the context it loaded into,
    /// skipping when Metal or the samples are unavailable.
    private func loadSample(_ path: String) throws -> (graph: Graph, context: Context)
    {
        let sampleURL = Self.repositoryRootURL.appending(path: "Fabric-Samples/Samples/\(path)")
        try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "Metal is unavailable.")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: sampleURL.path),
                          "Fabric-Samples is not checked out. Run: git submodule update --init --checkout Fabric-Samples")

        let context = try GraphBenchmark.makeEditorContext()
        return (try GraphBenchmark.loadGraph(at: sampleURL, context: context), context)
    }

    func testModelIteration() throws
    {
        let expectedIterationCount = 200
        let sample = try loadSample("7 - Iteration/Model Iteration.fabric")

        let iterators = sample.graph.nodes.compactMap { $0 as? IteratorNode }
        guard iterators.count == 1,
              iterators[0].inputIteratonCount.value == expectedIterationCount,
              iterators[0].subGraph.nodes.contains(where: { $0 is ModelMeshNode })
        else
        {
            throw GraphExecutionTestFailure("Model Iteration is not one Iterator of \(expectedIterationCount) model meshes")
        }

        try GraphBenchmark.run(graph: sample.graph, label: "Model Iteration", context: sample.context)
    }

    func test3DScene4K() throws
    {
        let sample = try loadSample("3 - 3D Scenes and Transforms/3a - 3D Scene.fabric")
        try GraphBenchmark.run(graph: sample.graph, label: "3a - 3D Scene 4K", context: sample.context, renderSize: GraphBenchmark.uhd4K)
    }

    func testRenderToImage4K() throws
    {
        let sample = try loadSample("5 - Subgraphs and Post Processing/5b - Render to Image.fabric")
        try GraphBenchmark.run(graph: sample.graph, label: "5b - Render to Image 4K", context: sample.context, renderSize: GraphBenchmark.uhd4K)
    }
}
