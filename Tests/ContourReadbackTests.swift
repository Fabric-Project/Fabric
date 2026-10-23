import Testing
import Foundation
import Metal
import Satin
@testable import Fabric

@Suite("Contour GPU readback", .serialized)
struct ContourReadbackTests {
    private final class ContourConsumer: Node {
        override class var name: String { "Contour Consumer" }
        override class var nodeType: Node.NodeType { .Utility }
        override class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
        override class var nodeTimeMode: Node.TimeMode { .None }
        override class var nodeDescription: String { "Consumes contour results for tests" }
        override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)] {
            super.registerPorts(context: context) + [
                ("input", NodePort<ContiguousArray<SIMD2<Float>>>(name: "Contour", kind: .Inlet))
            ]
        }
        var input: NodePort<ContiguousArray<SIMD2<Float>>> { port(named: "input") }
        var pointCount = 0
        override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo,
                              renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
            pointCount = input.value?.count ?? 0
        }
    }

    @Test("Graph scheduling delivers contour results downstream", arguments: GPUResultDeliveryMode.allCases)
    func graphDelivery(mode: GPUResultDeliveryMode) throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let node = ContourPathNode(context: harness.context)
        node.resultDeliveryMode = mode
        node.inputMask.value = try mask(harness)
        node.inputMaxSegments.value = 32
        let consumer = ContourConsumer(context: harness.context)
        graph.addNode(node)
        graph.addNode(consumer)
        graph.connect(node.outputContour, to: consumer.input)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }
        for frameNumber in 0...1 {
            let commands = try #require(renderer.makeCommandBuffer())
            try renderer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: frameNumber),
                                 renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
            if frameNumber == 0 && mode == .nextFrame { #expect(consumer.pointCount == 0) }
            else { #expect(consumer.pointCount >= 2) }
            commands.commit()
            commands.waitUntilCompleted()
            #expect(commands.status == .completed)
        }
    }

    private func mask(_ harness: GraphExecutionTestHarness) throws -> FabricImage {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: 4, height: 4, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = try #require(harness.context.device.makeTexture(descriptor: descriptor))
        let values: [Float] = Array(repeating: [Float(0), 0, 1, 1], count: 4).flatMap { $0 }
        values.withUnsafeBytes { bytes in
            if let address = bytes.baseAddress {
                texture.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0,
                                withBytes: address, bytesPerRow: 4 * MemoryLayout<Float>.stride)
            }
        }
        return .unmanaged(texture: texture)
    }

    @Test("A static mask delivers a deferred contour even when its inputs no longer change")
    func nextFrameContour() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let node = ContourPathNode(context: harness.context)
        node.resultDeliveryMode = .nextFrame
        node.inputMaxSegments.value = 32
        node.inputMask.value = try mask(harness)
        let commands = try #require(harness.renderer.makeCommandBuffer())
        try node.execute(renderer: harness.renderer, executionInfo: harness.makeExecutionInfo(frameNumber: 0),
                         renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
        #expect(node.outputContour.value == nil)
        #expect(commands.status == .notEnqueued)
        commands.commit()
        commands.waitUntilCompleted()
        #expect(node.outputContour.value == nil, "GPU completion never publishes to a port")
        node.markClean()
        #expect(node.isDirty, "A clean processor must remain scheduled until its deferred result is consumed")
        let next = try #require(harness.renderer.makeCommandBuffer())
        try node.execute(renderer: harness.renderer, executionInfo: harness.makeExecutionInfo(frameNumber: 1),
                         renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: next)
        let points = try #require(node.outputContour.value)
        #expect(points.count >= 2)
        node.markClean()
        #expect(!node.isDirty, "A delivered static result needs no further polling")
        next.commit()
        next.waitUntilCompleted()
    }

    @Test("An ambiguous cell initializes the last available segment slot")
    func cappedAmbiguousCell() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: 2, height: 2, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = try #require(harness.context.device.makeTexture(descriptor: descriptor))
        let values: [Float] = [1, 0, 0, 1]
        values.withUnsafeBytes { bytes in
            if let address = bytes.baseAddress {
                texture.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, withBytes: address, bytesPerRow: 8)
            }
        }
        let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fabric/Compute/MarchingSquares.metal")
        let library = try harness.context.device.makeLibrary(source: String(contentsOf: sourceURL, encoding: .utf8), options: nil)
        let function = try #require(library.makeFunction(name: "Update"))
        let pipeline = try harness.context.device.makeComputePipelineState(function: function)
        let segments = try #require(harness.context.device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared))
        segments.contents().storeBytes(of: SIMD4<Float>(repeating: 99), as: SIMD4<Float>.self)
        let counter = try #require(harness.context.device.makeBuffer(length: 4, options: .storageModeShared))
        counter.contents().storeBytes(of: UInt32(0), as: UInt32.self)
        struct Uniforms { var iso: Float = 0.5; var maxSegments: UInt32 = 1 }
        var uniforms = Uniforms()
        let commands = try #require(harness.renderer.makeCommandBuffer())
        let compute = try #require(commands.makeComputeCommandEncoder())
        compute.setComputePipelineState(pipeline)
        compute.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        compute.setBuffer(segments, offset: 0, index: 1)
        compute.setBuffer(counter, offset: 0, index: 2)
        compute.setTexture(texture, index: 0)
        compute.dispatchThreads(.init(width: 1, height: 1, depth: 1), threadsPerThreadgroup: .init(width: 1, height: 1, depth: 1))
        compute.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)
        #expect(counter.contents().load(as: UInt32.self) == 2)
        let segment = segments.contents().load(as: SIMD4<Float>.self)
        #expect(segment != SIMD4<Float>(repeating: 99), "The final available slot must be written even when the second segment exceeds the cap")
        #expect((0..<4).allSatisfy { segment[$0].isFinite && segment[$0] >= 0 && segment[$0] <= 1 })
    }

    @Test("A discarded frame retries a static deferred analysis")
    func abandonedFrameRetries() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let node = ContourPathNode(context: harness.context)
        node.resultDeliveryMode = .nextFrame
        node.inputMask.value = try mask(harness)
        node.inputMaxSegments.value = 32
        try autoreleasepool {
            let commands = try #require(harness.renderer.makeCommandBuffer())
            try node.execute(renderer: harness.renderer, executionInfo: harness.makeExecutionInfo(frameNumber: 0),
                             renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
            node.markClean()
        }
        #expect(node.isDirty)
        let retry = try #require(harness.renderer.makeCommandBuffer())
        try node.execute(renderer: harness.renderer, executionInfo: harness.makeExecutionInfo(frameNumber: 1),
                         renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: retry)
        node.markClean()
        retry.commit()
        retry.waitUntilCompleted()
        let next = try #require(harness.renderer.makeCommandBuffer())
        try node.execute(renderer: harness.renderer, executionInfo: harness.makeExecutionInfo(frameNumber: 2),
                         renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: next)
        #expect(try #require(node.outputContour.value).count >= 2)
        next.commit()
        next.waitUntilCompleted()
    }

    @Test("Same-frame contour reads GPU output before returning and preserves the frame buffer")
    func sameFrameContour() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let node = ContourPathNode(context: harness.context)
        node.inputMaxSegments.value = 32
        node.inputMask.value = try mask(harness)
        let commands = try #require(harness.renderer.makeCommandBuffer())
        try node.execute(renderer: harness.renderer, executionInfo: harness.makeExecutionInfo(),
                         renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
        let points = try #require(node.outputContour.value)
        #expect(points.count >= 2)
        #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        #expect(commands.status == .notEnqueued)
        commands.commit()
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)
    }
}
