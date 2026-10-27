import Testing
import Metal
import Satin
@testable import Fabric

/// Images come from the context's GPU allocator, and Render to Image's own renderer shares it, so
/// a document's renderers share heaps instead of each reserving its own.
@Suite("Graph image allocation", .serialized)
struct GraphImageAllocatorTests {
    @Test("Render to Image nodes share their document's allocator and its heaps")
    func renderToImageSharesTheAllocator() throws {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let outer = Graph(context: harness.context)
        var imageNodes: [DeferredSubgraphNode] = []
        for _ in 0 ..< 5 {
            let imageNode = DeferredSubgraphNode(context: harness.context, subGraph: Graph(context: harness.context))
            imageNode.inputWidth.value = 64
            imageNode.inputHeight.value = 64
            outer.addNode(imageNode)
            imageNodes.append(imageNode)
        }
        let renderer = harness.graphRenderer(for: outer)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }
        for frame in 0 ..< 3 {
            try harness.render(graph: outer, executionInfo: harness.makeExecutionInfo(frameNumber: frame))
        }

        let allocator = harness.context.gpuAllocator
        for imageNode in imageNodes {
            #expect(imageNode.graphRenderer.context.gpuAllocator === allocator)
            #expect(try #require(imageNode.outputColorTexture.value).texture.heap != nil)
        }
        let statistics = allocator.statistics(for: .gpuOnly)
        #expect(statistics.heapCount > 0)
        #expect(statistics.heapBytes <= 2 * GPUAllocator.Configuration().heapGrowthSize,
                "five Render to Image nodes fit in shared heaps, not a heap each")
    }

    @Test("Graph images use the requested storage and come from the context's allocator")
    func imagesComeFromTheAllocator() throws {
        guard let harness = GraphExecutionTestHarness(renderWidth: 4, renderHeight: 4) else { return }
        let renderer = harness.renderer
        let privateImage = try renderer.newImage(withWidth: 8, height: 8)
        let sharedImage = try renderer.makeImage(width: 8, height: 8, pixelFormat: .rgba8Unorm, storageMode: .shared)
        #expect(privateImage.texture.heap?.storageMode == .private)
        #expect(sharedImage.texture.heap?.storageMode == .shared)
        #expect(renderer.context.gpuAllocator.statistics(for: .gpuOnly).heapCount > 0)
        #expect(renderer.context.gpuAllocator.statistics(for: .cpuReads).heapCount > 0)
    }
}
