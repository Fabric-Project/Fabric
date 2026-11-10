import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

@Suite("Stream nodes", .serialized)
struct StreamNodeTests
{
    /// Pulls whatever it is wired to and records each value it sees.
    private final class RecordingConsumer: Node
    {
        override class var name: String { "Recording Consumer" }
        override class var nodeType: Node.NodeType { .Utility }
        override class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
        override class var nodeTimeMode: Node.TimeMode { .None }
        override class var nodeDescription: String { "Records values for tests" }
        override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
        {
            super.registerPorts(context: context) + [("input", NodePort<PortValue>(name: "Value", kind: .Inlet))]
        }
        var input: NodePort<PortValue> { port(named: "input") }
        var recorded: [PortValue?] = []
        override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo,
                              renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
        {
            recorded.append(input.value)
        }
    }

    /// Sends a different Float stream on each Iterator iteration.
    private final class IteratedStream: Node
    {
        override class var name: String { "Iterated Stream" }
        override class var nodeType: Node.NodeType { .Utility }
        override class var nodeExecutionMode: Node.ExecutionMode { .Provider }
        override class var nodeTimeMode: Node.TimeMode { .None }
        override class var nodeDescription: String { "Supplies a distinct stream for each iteration" }
        override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
        {
            super.registerPorts(context: context) + [("output", NodePort<GPUStream<Float>>(name: "Stream", kind: .Outlet))]
        }
        var output: NodePort<GPUStream<Float>> { port(named: "output") }
        var streams: [GPUStream<Float>] = []
        override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo,
                              renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
        {
            output.send(streams[executionInfo.iterationInfo?.currentIteration ?? 0], force: true)
        }
    }

    private func runFrames(_ graph: Graph, _ harness: GraphExecutionTestHarness, frames: ClosedRange<Int>) throws
    {
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }
        for frame in frames
        {
            let commands = try #require(renderer.makeCommandBuffer())
            try renderer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: frame),
                                 renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
            commands.commit()
            commands.waitUntilCompleted()
            #expect(commands.status == .completed)
        }
    }

    /// Array to Stream → Stream to Array → a recording consumer, for one element type.
    private func roundTripGraph(_ harness: GraphExecutionTestHarness, type: PortType, mode: GPUResultDeliveryMode)
        -> (graph: Graph, upload: ArrayToStreamNode, readback: StreamToArrayNode, consumer: RecordingConsumer)
    {
        let graph = Graph(context: harness.context)
        let upload = ArrayToStreamNode(context: harness.context, strategy: type)
        let readback = StreamToArrayNode(context: harness.context, strategy: type)
        readback.resultDeliveryMode = mode
        let consumer = RecordingConsumer(context: harness.context)
        graph.addNode(upload)
        graph.addNode(readback)
        graph.addNode(consumer)
        graph.connect(upload.port(named: "outputStream"), to: readback.port(named: "inputStream"))
        graph.connect(readback.port(named: "outputArray"), to: consumer.input)
        return (graph, upload, readback, consumer)
    }

    private func roundTrip<Element: GPUStreamElement>(_ values: ContiguousArray<Element>, type: PortType) throws -> ContiguousArray<Element>?
    {
        let harness = try #require(GraphExecutionTestHarness())
        let (graph, upload, readback, _) = roundTripGraph(harness, type: type, mode: .sync)
        let input = try #require(upload.findPort(named: "inputArray") as NodePort<ContiguousArray<Element>>?)
        input.value = values
        try runFrames(graph, harness, frames: 0...0)
        return (readback.findPort(named: "outputArray") as NodePort<ContiguousArray<Element>>?)?.value
    }

    @Test("Every element type survives Array to Stream and Stream to Array")
    func everyTypeRoundTrips() throws
    {
        #expect(try roundTrip(ContiguousArray<Float>([1, -2.5, 3]), type: .Float) == [1, -2.5, 3])
        #expect(try roundTrip(ContiguousArray<Int>([7, -8, 9]), type: .Int) == [7, -8, 9])
        #expect(try roundTrip(ContiguousArray([simd_float2(1, 2), simd_float2(3, 4)]), type: .Vector2) == [simd_float2(1, 2), simd_float2(3, 4)])
        #expect(try roundTrip(ContiguousArray([simd_float3(1, 2, 3), simd_float3(4, 5, 6)]), type: .Vector3) == [simd_float3(1, 2, 3), simd_float3(4, 5, 6)])
        #expect(try roundTrip(ContiguousArray([simd_float4(1, 2, 3, 4)]), type: .Vector4) == [simd_float4(1, 2, 3, 4)])
        let rotation = simd_quatf(angle: 0.5, axis: simd_float3(0, 1, 0))
        #expect(try roundTrip(ContiguousArray([rotation]), type: .Quaternion) == [rotation])
        #expect(try roundTrip(ContiguousArray<Float>(), type: .Float) == [])
    }

    @Test("Ints outside 32 bits are clamped and the node says so")
    func intsClamp() throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let (graph, upload, readback, _) = roundTripGraph(harness, type: .Int, mode: .sync)
        let input = try #require(upload.findPort(named: "inputArray") as NodePort<ContiguousArray<Int>>?)
        input.value = [Int.max, -5, Int.min]
        try runFrames(graph, harness, frames: 0...0)

        let output = (readback.findPort(named: "outputArray") as NodePort<ContiguousArray<Int>>?)?.value
        #expect(output == [Int(Int32.max), -5, Int(Int32.min)])
        #expect(upload.deriveStatuses().count == 1)
    }

    @Test("Next Frame delivers on a later frame without waiting; Same Frame delivers at once")
    func deliveryTiming() throws
    {
        for mode in GPUResultDeliveryMode.allCases
        {
            let harness = try #require(GraphExecutionTestHarness())
            let (graph, upload, _, consumer) = roundTripGraph(harness, type: .Float, mode: mode)
            let input = try #require(upload.findPort(named: "inputArray") as NodePort<ContiguousArray<Float>>?)
            input.value = [4, 5]
            try runFrames(graph, harness, frames: 0...1)

            let expected = ContiguousArray<Float>([4, 5]).toPortValue()
            if mode == .sync
            {
                #expect(consumer.recorded.first == expected)
            }
            else
            {
                #expect(consumer.recorded.first == .some(nil))
                #expect(consumer.recorded.last == expected)
            }
        }
    }

    @Test("Stream to Array reads only the elements a GPU count says are valid")
    func gpuCountLimitsReadback() throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let attribute = try PublishedAttribute.publishing(ContiguousArray<Float>([1, 2, 3, 4]), scalar: .float32, components: 1,
                                                          allocator: harness.context.gpuAllocator)
        let countBuffer = try #require(harness.context.device.makeBuffer(length: 32, options: .storageModeShared))
        countBuffer.contents().storeBytes(of: UInt32(2), toByteOffset: 16, as: UInt32.self)

        let graph = Graph(context: harness.context)
        let readback = StreamToArrayNode(context: harness.context, strategy: PortType.Float)
        let consumer = RecordingConsumer(context: harness.context)
        graph.addNode(readback)
        graph.addNode(consumer)
        graph.connect(readback.port(named: "outputArray"), to: consumer.input)
        let input = try #require(readback.findPort(named: "inputStream") as NodePort<GPUStream<Float>>?)
        input.value = try GPUStream(attribute: attribute, count: .gpu(try PointsDrawArguments(buffer: countBuffer, offset: 16), capacity: 4))
        try runFrames(graph, harness, frames: 0...0)

        #expect((readback.findPort(named: "outputArray") as NodePort<ContiguousArray<Float>>?)?.value == [1, 2])
    }

    @Test("Stream to Array decodes half-precision storage")
    func halfStorageDecodes() throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        // 1, -2.5, 65504 and 2⁻²⁴ (the smallest subnormal) as IEEE halves.
        let halves = ContiguousArray<UInt16>([0x3C00, 0xC100, 0x7BFF, 0x0001])
        let attribute = try PublishedAttribute.publishing(halves, scalar: .float16, components: 1, allocator: harness.context.gpuAllocator)

        let graph = Graph(context: harness.context)
        let readback = StreamToArrayNode(context: harness.context, strategy: PortType.Float)
        let consumer = RecordingConsumer(context: harness.context)
        graph.addNode(readback)
        graph.addNode(consumer)
        graph.connect(readback.port(named: "outputArray"), to: consumer.input)
        let input = try #require(readback.findPort(named: "inputStream") as NodePort<GPUStream<Float>>?)
        input.value = try GPUStream(attribute: attribute)
        try runFrames(graph, harness, frames: 0...0)

        let output = (readback.findPort(named: "outputArray") as NodePort<ContiguousArray<Float>>?)?.value
        #expect(output == [1, -2.5, 65504, Float(sign: .plus, exponent: -24, significand: 1)])
    }

    /// A Float stream of `attribute` read back through Stream to Array in one frame.
    private func readBackFloats(_ attribute: PublishedAttribute, _ harness: GraphExecutionTestHarness) throws -> ContiguousArray<Float>?
    {
        let graph = Graph(context: harness.context)
        let readback = StreamToArrayNode(context: harness.context, strategy: PortType.Float)
        let consumer = RecordingConsumer(context: harness.context)
        graph.addNode(readback)
        graph.addNode(consumer)
        graph.connect(readback.port(named: "outputArray"), to: consumer.input)
        let input = try #require(readback.findPort(named: "inputStream") as NodePort<GPUStream<Float>>?)
        input.value = try GPUStream(attribute: attribute)
        try runFrames(graph, harness, frames: 0...0)
        return (readback.findPort(named: "outputArray") as NodePort<ContiguousArray<Float>>?)?.value
    }

    @Test("Half streams of any length read back, from memory the CPU can see or GPU-only memory")
    func oddLengthHalvesReadBack() throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        // One half: two bytes, short of a 4-byte copy.
        let one = try PublishedAttribute.publishing(ContiguousArray<UInt16>([0x3C00]), scalar: .float16, components: 1,
                                                    allocator: harness.context.gpuAllocator)
        #expect(try readBackFloats(one, harness) == [1])

        #if os(macOS)
        // Three halves in six bytes of memory the CPU can't read in place: no aligned window fits,
        // so the byte-copy kernel takes them.
        var halves: [UInt16] = [0x3C00, 0xC100, 0x7BFF]
        let managed = try #require(harness.context.device.makeBuffer(bytes: &halves, length: 6, options: .storageModeManaged))
        let attribute = PublishedAttribute(adopting: managed, layout: AttributeLayout(scalar: .float16, components: 1, byteOffset: 0, byteStride: 2), count: 3)
        #expect(try readBackFloats(attribute, harness) == [1, -2.5, 65504])
        #endif
    }

    @Test("Deferred stream readback delivers each Iterator iteration its own result")
    func iteratorDelivery() throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        func run(mode: GPUResultDeliveryMode) throws -> [PortValue?]
        {
            let graph = Graph(context: harness.context)
            let iterator = IteratorNode(context: harness.context)
            iterator.inputIteratonCount.value = 3
            let source = IteratedStream(context: harness.context)
            source.streams = try (0..<3).map { iteration in
                let values = ContiguousArray<Float>([Float(iteration), Float(iteration) + 0.5])
                return try GPUStream(attribute: try PublishedAttribute.publishing(values, scalar: .float32, components: 1,
                                                                                  allocator: harness.context.gpuAllocator))
            }
            let readback = StreamToArrayNode(context: harness.context, strategy: PortType.Float)
            readback.resultDeliveryMode = mode
            let consumer = RecordingConsumer(context: harness.context)
            for node in [source, readback, consumer] as [Node] { iterator.subGraph.addNode(node) }
            iterator.subGraph.connect(source.output, to: readback.port(named: "inputStream"))
            iterator.subGraph.connect(readback.port(named: "outputArray"), to: consumer.input)
            graph.addNode(iterator)
            try runFrames(graph, harness, frames: 0...1)
            return consumer.recorded
        }

        let synchronous = try run(mode: .sync)
        let deferred = try run(mode: .async)
        #expect(synchronous.count == 6)
        let expected: [PortValue?] = (0..<3).map { ContiguousArray<Float>([Float($0), Float($0) + 0.5]).toPortValue() }
        #expect(Array(synchronous.prefix(3)) == expected)
        #expect(deferred.prefix(3).allSatisfy { $0 == nil })
        #expect(Array(deferred.suffix(3)) == Array(synchronous.prefix(3)))
    }

    @Test("Changing the delivery mode reads the unchanged input again")
    func modeChangeRereads() throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let (graph, upload, readback, _) = roundTripGraph(harness, type: .Float, mode: .async)
        let input = try #require(upload.findPort(named: "inputArray") as NodePort<ContiguousArray<Float>>?)
        input.value = [6]
        let output = try #require(readback.findPort(named: "outputArray") as NodePort<ContiguousArray<Float>>?)

        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }
        func frame(_ number: Int) throws
        {
            let commands = try #require(renderer.makeCommandBuffer())
            try renderer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: number),
                                 renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
            commands.commit()
            commands.waitUntilCompleted()
        }

        try frame(0)
        try frame(1)
        #expect(output.value == [6])

        output.value = nil
        readback.resultDeliveryMode = .sync
        try frame(2)
        #expect(output.value == [6])
        #expect(readback.deriveStatuses().count == 1)
    }
}
