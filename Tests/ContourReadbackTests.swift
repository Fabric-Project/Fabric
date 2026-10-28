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
        var observedCenters: [Float?] = []
        override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo,
                              renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
            pointCount = input.value?.count ?? 0
            observedCenters.append(input.value.flatMap { points in
                guard let first = points.first else { return nil }
                let extent = points.reduce((min: first.x, max: first.x)) { (min($0.min, $1.x), max($0.max, $1.x)) }
                return (extent.min + extent.max) * 0.5
            })
        }
    }

    private final class IteratedMask: Node {
        override class var name: String { "Iterated Mask" }
        override class var nodeType: Node.NodeType { .Utility }
        override class var nodeExecutionMode: Node.ExecutionMode { .Provider }
        override class var nodeTimeMode: Node.TimeMode { .None }
        override class var nodeDescription: String { "Supplies a distinct mask for each iteration" }
        override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)] {
            super.registerPorts(context: context) + [("output", NodePort<FabricImage>(name: "Mask", kind: .Outlet))]
        }
        var output: NodePort<FabricImage> { port(named: "output") }
        var masks: [FabricImage] = []
        override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo,
                              renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
            output.send(masks[executionInfo.iterationInfo?.currentIteration ?? 0], force: true)
        }
    }

    @Test("Deferred contour results preserve each Iterator occurrence")
    func iteratorDelivery() throws {
        let harness = try #require(GraphExecutionTestHarness())
        func run(mode: GPUResultDeliveryMode) throws -> [Int?] {
            let graph = Graph(context: harness.context)
            let iterator = IteratorNode(context: harness.context)
            iterator.inputIteratonCount.value = 3
            let source = IteratedMask(context: harness.context)
            source.masks = try (0..<3).map { try mask(harness, boundary: 4 + $0 * 16) }
            let contour = ContourPathNode(context: harness.context)
            contour.resultDeliveryMode = mode
            contour.inputMaxSegments.value = 128
            contour.inputJoinEpsilon.value = 0.25
            let consumer = ContourConsumer(context: harness.context)
            for node in [source, contour, consumer] { iterator.subGraph.addNode(node) }
            iterator.subGraph.connect(source.output, to: contour.inputMask)
            iterator.subGraph.connect(contour.outputContour, to: consumer.input)
            graph.addNode(iterator)
            let renderer = harness.graphRenderer(for: graph)
            try renderer.startExecution()
            defer { try? renderer.stopExecution() }
            for frame in 0...1 {
                let commands = try #require(renderer.makeCommandBuffer())
                try renderer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: frame),
                    renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
                commands.commit()
                commands.waitUntilCompleted()
                #expect(commands.status == .completed)
            }
            // Identify the widely separated masks without depending on contour start-point order.
            return consumer.observedCenters.map { $0.map { Int($0 / 16) } }
        }
        let synchronous = try run(mode: .sync)
        let deferred = try run(mode: .async)
        #expect(synchronous.count == 6)
        #expect(Array(synchronous.prefix(3)) == [0, 1, 2], "The synchronous control visits each distinct mask")
        #expect(deferred.prefix(3).allSatisfy { $0 == nil })
        #expect(Array(deferred.suffix(3)) == Array(synchronous.prefix(3)))
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
            if frameNumber == 0 && mode == .async { #expect(consumer.pointCount == 0) }
            else { #expect(consumer.pointCount >= 2) }
            commands.commit()
            commands.waitUntilCompleted()
            #expect(commands.status == .completed)
        }
    }

    private func mask(_ harness: GraphExecutionTestHarness, boundary: Int? = nil) throws -> FabricImage {
        let size = boundary == nil ? 4 : 64
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: size, height: size, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = try #require(harness.context.device.makeTexture(descriptor: descriptor))
        let values: [Float] = (0..<(size * size)).map { index in
            guard let boundary else { return index % size < 2 ? 0 : 1 }
            let column = index % size
            let row = index / size
            return column >= boundary && column < boundary + 2 && row >= 2 && row < 6 ? 1 : 0
        }
        values.withUnsafeBytes { bytes in
            if let address = bytes.baseAddress {
                texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
                                withBytes: address, bytesPerRow: size * MemoryLayout<Float>.stride)
            }
        }
        return .unmanaged(texture: texture)
    }

    private func graph(for node: ContourPathNode, harness: GraphExecutionTestHarness) -> (graph: Graph, renderer: GraphRenderer) {
        let graph = Graph(context: harness.context)
        let consumer = ContourConsumer(context: harness.context)
        graph.addNode(node)
        graph.addNode(consumer)
        graph.connect(node.outputContour, to: consumer.input)
        return (graph, harness.graphRenderer(for: graph))
    }

    @Test("A static mask delivers a deferred contour even when its inputs no longer change")
    func nextFrameContour() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let node = ContourPathNode(context: harness.context)
        node.resultDeliveryMode = .async
        node.inputMaxSegments.value = 32
        node.inputMask.value = try mask(harness)
        let (graph, renderer) = graph(for: node, harness: harness)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }
        let commands = try #require(renderer.makeCommandBuffer())
        try renderer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: 0),
                             renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
        #expect(node.outputContour.value == nil)
        #expect(commands.status == .notEnqueued)
        commands.commit()
        commands.waitUntilCompleted()
        #expect(node.outputContour.value == nil, "GPU completion never publishes to a port")
        #expect(!node.isDirty, "The graph handles completed results without node-level polling")
        let next = try #require(renderer.makeCommandBuffer())
        #expect(node.outputContour.value == nil, "Decoding stages results until the node's execution")
        try renderer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: 1),
                             renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: next)
        #expect(try #require(node.outputContour.value).count >= 2)
        #expect(!node.isDirty)
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
        node.resultDeliveryMode = .async
        node.inputMask.value = try mask(harness)
        node.inputMaxSegments.value = 32
        let (graph, renderer) = graph(for: node, harness: harness)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }
        try autoreleasepool {
            let commands = try #require(renderer.makeCommandBuffer())
            try renderer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: 0),
                                 renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
        }
        let retry = try #require(renderer.makeCommandBuffer())
        try renderer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: 1),
                             renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: retry)
        retry.commit()
        retry.waitUntilCompleted()
        let next = try #require(renderer.makeCommandBuffer())
        try renderer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: 2),
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
