import Foundation
import Metal
import Satin
import XCTest
@testable import Fabric

/// Phase 1 measurements for published points, through `GraphBenchmark` (Release numbers:
/// `swift test -c release -Xswiftc -enable-testing`). Compare static against animated, and both
/// against main's Model Iteration, in the same session.
final class PointsPerformanceBenchmark: XCTestCase
{
    private static let iterationCount = 200

    /// An Iterator of `iterationCount` points meshes spread across x.
    private func makeIteratorGraph(context: Context, publishesOnce: Bool) -> Graph
    {
        let graph = Graph(context: context)
        let iterator = IteratorNode(context: context)
        iterator.inputIteratonCount.value = Self.iterationCount
        let offsets = (0 ..< Self.iterationCount).map { Float($0) / Float(Self.iterationCount - 1) * 1.6 - 0.8 }
        let producer = addPointsMesh(to: iterator.subGraph, context: context, offsets: offsets, publishesOnce: publishesOnce)
        producer.halfSize = 0.02
        graph.addNode(iterator)
        return graph
    }

    /// Steady state should do no points work: nothing is published after the first frame.
    func testStaticPointsIteration() throws
    {
        try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "Metal is unavailable.")
        let context = try GraphBenchmark.makeEditorContext()
        try GraphBenchmark.run(graph: makeIteratorGraph(context: context, publishesOnce: true),
                               label: "Points Iteration (static)", context: context)
    }

    /// Every iteration publishes new points every frame: the per-version cost (allocator buffer,
    /// version, vertex descriptor rebuild in `setPoints`).
    func testAnimatedPointsIteration() throws
    {
        try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "Metal is unavailable.")
        let context = try GraphBenchmark.makeEditorContext()
        try GraphBenchmark.run(graph: makeIteratorGraph(context: context, publishesOnce: false),
                               label: "Points Iteration (animated)", context: context)
    }
}
