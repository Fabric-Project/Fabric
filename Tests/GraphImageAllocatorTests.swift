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
        #expect(statistics.heapCount == 1, "five Render to Image nodes fit in one shared heap, not a heap each")
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

    @Test("Renderer cleanup gives empty heaps back and keeps heaps with live images")
    func cleanupTrimsEmptyHeaps() throws {
        guard let released = GraphExecutionTestHarness(renderWidth: 4, renderHeight: 4) else { return }
        do { _ = try released.renderer.newImage(withWidth: 8, height: 8) }
        #expect(released.context.gpuAllocator.statistics(for: .gpuOnly).heapCount == 1)
        try released.renderer.cleanup()
        #expect(released.context.gpuAllocator.statistics(for: .gpuOnly).heapCount == 0)

        guard let held = GraphExecutionTestHarness(renderWidth: 4, renderHeight: 4) else { return }
        let liveImage = try held.renderer.newImage(withWidth: 8, height: 8)
        try held.renderer.cleanup()
        #expect(held.context.gpuAllocator.statistics(for: .gpuOnly).heapCount == 1)
        #expect(liveImage.texture.heap != nil)
    }

    @Test("Full-resolution 4K images come from shared heaps every frame, never the device")
    func fourKImagesUseHeaps() throws {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let outer = Graph(context: harness.context)
        var imageNodes: [DeferredSubgraphNode] = []
        for _ in 0 ..< 3 {
            let imageNode = DeferredSubgraphNode(context: harness.context, subGraph: Graph(context: harness.context))
            imageNode.inputWidth.value = 3840
            imageNode.inputHeight.value = 2160
            outer.addNode(imageNode)
            imageNodes.append(imageNode)
        }
        let renderer = harness.graphRenderer(for: outer)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }

        let allocator = harness.context.gpuAllocator
        try harness.render(graph: outer, executionInfo: harness.makeExecutionInfo(frameNumber: 0))
        let warmHeapCount = allocator.statistics(for: .gpuOnly).heapCount
        for frame in 1 ..< 6 {
            try harness.render(graph: outer, executionInfo: harness.makeExecutionInfo(frameNumber: frame))
        }

        for imageNode in imageNodes {
            let texture = try #require(imageNode.outputColorTexture.value).texture
            #expect(texture.width == 3840)
            #expect(texture.heap != nil)
        }
        let statistics = allocator.statistics(for: .gpuOnly)
        #expect(statistics.dedicatedCount == 0)
        #expect(statistics.fallbackCount == 0)
        #expect(statistics.heapCount == warmHeapCount, "steady frames reuse the heaps the first frame made")
    }

    @Test("A 4K image of each common format comes from a heap")
    func fourKFormatsUseHeaps() throws {
        guard let harness = GraphExecutionTestHarness(renderWidth: 4, renderHeight: 4) else { return }
        for format in [MTLPixelFormat.bgra8Unorm, .rgba16Float, .rgba32Float] {
            let image = try harness.renderer.newImage(withWidth: 3840, height: 2160, format: format)
            #expect(image.texture.heap != nil, "\(format)")
        }
        #expect(harness.context.gpuAllocator.statistics(for: .gpuOnly).dedicatedCount == 0)
    }
}
