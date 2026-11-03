import Foundation
import Metal
import XCTest
@testable import Fabric

/// Runs with the rest of the tests. See GraphBenchmark for where results go and how to get real numbers.
final class GraphPerformanceBenchmark: XCTestCase
{
    private static let repositoryRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testModelIteration() throws
    {
        let sampleURL = Self.repositoryRootURL.appending(path: "Fabric-Samples/Samples/7 - Iteration/Model Iteration.fabric")
        let expectedIterationCount = 200

        try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "Metal is unavailable.")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: sampleURL.path),
                          "Fabric-Samples is not checked out. Run: git submodule update --init --checkout Fabric-Samples")

        let context = try GraphBenchmark.makeEditorContext()
        let graph = try GraphBenchmark.loadGraph(at: sampleURL, context: context)

        let iterators = graph.nodes.compactMap { $0 as? IteratorNode }
        guard iterators.count == 1,
              iterators[0].inputIteratonCount.value == expectedIterationCount,
              iterators[0].subGraph.nodes.contains(where: { $0 is ModelMeshNode })
        else
        {
            throw GraphExecutionTestFailure("Model Iteration is not one Iterator of \(expectedIterationCount) model meshes")
        }

        try GraphBenchmark.run(graph: graph, label: "Model Iteration", context: context)
    }
}
