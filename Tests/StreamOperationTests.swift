import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

@Suite("Stream Feedback, Math, Select, Random, Noise and Ramp", .serialized)
struct StreamOperationTests
{
    /// Pulls whatever it is wired to, so the nodes before it run.
    private final class PullingConsumer: Node
    {
        override class var name: String { "Pulling Consumer" }
        override class var nodeType: Node.NodeType { .Utility }
        override class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
        override class var nodeTimeMode: Node.TimeMode { .None }
        override class var nodeDescription: String { "Pulls values for tests" }
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

    private func stream<Element: GPUStreamElement>(_ values: ContiguousArray<Element>, _ harness: GraphExecutionTestHarness) throws -> GPUStream<Element>
    {
        try GPUStream(attribute: try Element.publishStream(values, allocator: harness.context.gpuAllocator).attribute)
    }

    /// Wires `outlet` through Stream to Array to a consumer in `graph`, and returns the array port.
    private func readback<Element: GPUStreamElement>(_ outlet: Fabric.Port, as _: Element.Type, type: PortType,
                                                     in graph: Graph, _ harness: GraphExecutionTestHarness) -> NodePort<ContiguousArray<Element>>?
    {
        let readback = StreamToArrayNode(context: harness.context, strategy: type)
        let consumer = PullingConsumer(context: harness.context)
        graph.addNode(readback)
        graph.addNode(consumer)
        graph.connect(outlet, to: readback.port(named: "inputStream"))
        graph.connect(readback.port(named: "outputArray"), to: consumer.input)
        return readback.findPort(named: "outputArray")
    }

    /// Runs `frames` frames of `graph` on one renderer, calling `afterFrame` with each frame's index.
    private func run(_ graph: Graph, frames: Int, _ harness: GraphExecutionTestHarness, afterFrame: (Int) throws -> Void = { _ in }) throws
    {
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }
        for frame in 0 ..< frames
        {
            let commands = try #require(renderer.makeCommandBuffer())
            try renderer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: frame),
                                 renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
            commands.commit()
            commands.waitUntilCompleted()
            #expect(commands.status == .completed)
            try afterFrame(frame)
        }
    }

    /// One frame of `outlet`, read back.
    private func readBack<Element: GPUStreamElement>(_ outlet: Fabric.Port, as element: Element.Type, type: PortType,
                                                     in graph: Graph, _ harness: GraphExecutionTestHarness) throws -> ContiguousArray<Element>?
    {
        let array = readback(outlet, as: element, type: type, in: graph, harness)
        try run(graph, frames: 1, harness)
        return array?.value
    }

    @Test("Stream Math adds a value to every element, and multiply-adds with a one-element stream applied to all")
    func mathOperates() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 16, renderHeight: 16) else { return }

        let graph = Graph(context: harness.context)
        let add = StreamMathNode(context: harness.context, strategy: PortType.Float)
        (add.findPort(named: "inputA") as NodePort<GPUStream<Float>>?)?.value = try stream([1, 2, 3], harness)
        (add.findPort(named: "inputBValue") as ParameterPort<Float>?)?.value = 10
        graph.addNode(add)
        #expect(try readBack(add.port(named: "outputStream"), as: Float.self, type: .Float, in: graph, harness) == [11, 12, 13])

        let multiplyGraph = Graph(context: harness.context)
        let multiplyAdd = StreamMathNode(context: harness.context, strategy: PortType.Float)
        multiplyAdd.operation = .multiplyAdd
        (multiplyAdd.findPort(named: "inputA") as NodePort<GPUStream<Float>>?)?.value = try stream([1, 2, 3], harness)
        (multiplyAdd.findPort(named: "inputB") as NodePort<GPUStream<Float>>?)?.value = try stream([2], harness)
        (multiplyAdd.findPort(named: "inputCValue") as ParameterPort<Float>?)?.value = 3
        multiplyGraph.addNode(multiplyAdd)
        #expect(try readBack(multiplyAdd.port(named: "outputStream"), as: Float.self, type: .Float, in: multiplyGraph, harness) == [7, 8, 9])
    }

    @Test("Stream Select picks A where the condition is above the threshold and B elsewhere")
    func selectPicks() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 16, renderHeight: 16) else { return }
        let graph = Graph(context: harness.context)
        let select = StreamSelectNode(context: harness.context, strategy: PortType.Vector3)
        select.inputCondition.value = try stream([1, -1, 1], harness)
        (select.findPort(named: "inputA") as NodePort<GPUStream<simd_float3>>?)?.value = try stream([[1, 1, 1], [2, 2, 2], [3, 3, 3]], harness)
        (select.findPort(named: "inputB") as NodePort<GPUStream<simd_float3>>?)?.value = try stream([[10, 10, 10], [20, 20, 20], [30, 30, 30]], harness)
        graph.addNode(select)
        #expect(try readBack(select.port(named: "outputStream"), as: simd_float3.self, type: .Vector3, in: graph, harness)
                == [[1, 1, 1], [20, 20, 20], [3, 3, 3]])
    }

    @Test("Random Stream gives Count elements in range, the same for the same seed")
    func randomIsSeeded() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 16, renderHeight: 16) else { return }

        func values(seed: Int) throws -> ContiguousArray<simd_float3>?
        {
            let graph = Graph(context: harness.context)
            let random = RandomStreamNode(context: harness.context, strategy: PortType.Vector3)
            random.inputCount.value = 64
            random.inputSeed.value = seed
            (random.findPort(named: "inputMinimum") as ParameterPort<simd_float3>?)?.value = [-2, -2, -2]
            (random.findPort(named: "inputMaximum") as ParameterPort<simd_float3>?)?.value = [2, 2, 2]
            graph.addNode(random)
            return try readBack(random.port(named: "outputStream"), as: simd_float3.self, type: .Vector3, in: graph, harness)
        }

        let first = try #require(try values(seed: 7))
        #expect(first.count == 64)
        #expect(first.allSatisfy { all($0 .>= simd_float3(repeating: -2)) && all($0 .<= simd_float3(repeating: 2)) })
        #expect(Set(first.map(\.x)).count > 32, "values vary")
        #expect(try values(seed: 7) == first)
        #expect(try values(seed: 8) != first)
    }

    @Test("Random Stream's Maximum starts at one")
    func randomMaximumDefault() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 16, renderHeight: 16) else { return }
        let random = RandomStreamNode(context: harness.context, strategy: PortType.Vector2)
        #expect((random.findPort(named: "inputMaximum") as ParameterPort<simd_float2>?)?.value == [1, 1])
    }

    @Test("Stream Ramp blends from Start Color at Minimum to End Color at Maximum, clamped")
    func rampColors() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 16, renderHeight: 16) else { return }
        let graph = Graph(context: harness.context)
        let ramp = StreamRampNode(context: harness.context)
        ramp.inputValues.value = try stream([-1, 0, 0.5, 1, 2], harness)
        ramp.inputStartColor.value = [0, 0, 0, 0]
        ramp.inputEndColor.value = [1, 1, 1, 1]
        graph.addNode(ramp)
        #expect(try readBack(ramp.outputColors, as: simd_float4.self, type: .Vector4, in: graph, harness)
                == [.zero, .zero, simd_float4(repeating: 0.5), .one, .one])
    }

    @Test("Stream Noise gives one finite, varying vector per position, curl or not")
    func noiseSamples() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 16, renderHeight: 16) else { return }
        for curl in [true, false]
        {
            let graph = Graph(context: harness.context)
            let noise = StreamNoiseNode(context: harness.context)
            noise.inputPositions.value = try stream(ContiguousArray((0 ..< 32).map { simd_float3(Float($0) * 0.37, Float($0) * 0.11, 0.5) }), harness)
            noise.inputCurl.value = curl
            graph.addNode(noise)
            let vectors = try #require(try readBack(noise.outputNoise, as: simd_float3.self, type: .Vector3, in: graph, harness))
            #expect(vectors.count == 32)
            #expect(vectors.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            #expect(Set(vectors.map(\.x)).count > 16, "curl \(curl): values vary")
        }
    }

    @Test("Stream Feedback carries a stream from frame to frame, starting from Initial, and Reset starts again")
    func feedbackAccumulates() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 16, renderHeight: 16) else { return }
        let graph = Graph(context: harness.context)
        let feedback = StreamFeedbackNode(context: harness.context, strategy: PortType.Float)
        (feedback.findPort(named: "inputInitial") as NodePort<GPUStream<Float>>?)?.value = try stream([0, 10], harness)
        let increment = StreamMathNode(context: harness.context, strategy: PortType.Float)
        (increment.findPort(named: "inputBValue") as ParameterPort<Float>?)?.value = 1
        graph.addNode(feedback)
        graph.addNode(increment)
        graph.connect(feedback.port(named: "outputStream"), to: increment.port(named: "inputA"))
        graph.connect(increment.port(named: "outputStream"), to: feedback.port(named: "inputStream"))
        let result = readback(increment.port(named: "outputStream"), as: Float.self, type: .Float, in: graph, harness)

        var seen: [ContiguousArray<Float>?] = []
        try run(graph, frames: 3, harness) { _ in seen.append(result?.value) }
        #expect(seen == [[1, 11], [2, 12], [3, 13]])

        feedback.inputReset.value = true
        try run(graph, frames: 1, harness)
        #expect(result?.value == [1, 11])
    }

    @Test("Stream Feedback keeps each Iterator iteration's loop apart")
    func feedbackPerIteration() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 16, renderHeight: 16) else { return }
        let graph = Graph(context: harness.context)
        let iterator = IteratorNode(context: harness.context)
        iterator.inputIteratonCount.value = 2
        let feedback = StreamFeedbackNode(context: harness.context, strategy: PortType.Float)
        (feedback.findPort(named: "inputInitial") as NodePort<GPUStream<Float>>?)?.value = try stream([0], harness)
        let increment = StreamMathNode(context: harness.context, strategy: PortType.Float)
        (increment.findPort(named: "inputBValue") as ParameterPort<Float>?)?.value = 1
        let readback = StreamToArrayNode(context: harness.context, strategy: PortType.Float)
        readback.resultDeliveryMode = .sync
        let consumer = PullingConsumer(context: harness.context)
        for node in [feedback, increment, readback, consumer] as [Node] { iterator.subGraph.addNode(node) }
        iterator.subGraph.connect(feedback.port(named: "outputStream"), to: increment.port(named: "inputA"))
        iterator.subGraph.connect(increment.port(named: "outputStream"), to: feedback.port(named: "inputStream"))
        iterator.subGraph.connect(increment.port(named: "outputStream"), to: readback.port(named: "inputStream"))
        iterator.subGraph.connect(readback.port(named: "outputArray"), to: consumer.input)
        graph.addNode(iterator)

        try run(graph, frames: 2, harness)
        let expected: [PortValue?] = [ContiguousArray<Float>([1]), [1], [2], [2]].map { $0.toPortValue() }
        #expect(consumer.recorded == expected)
    }

    @Test("An empty stream stays an empty stream, not a missing one")
    func emptyStreamStaysEmpty() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 16, renderHeight: 16) else { return }
        let graph = Graph(context: harness.context)
        let math = StreamMathNode(context: harness.context, strategy: PortType.Float)
        (math.findPort(named: "inputA") as NodePort<GPUStream<Float>>?)?.value = try stream([], harness)
        graph.addNode(math)
        #expect(try readBack(math.port(named: "outputStream"), as: Float.self, type: .Float, in: graph, harness) == [])
    }

    @Test("Stream Feedback held on Reset sends Initial once, so nothing after it runs again")
    func unchangedFeedbackIsNotResent() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 16, renderHeight: 16) else { return }
        let graph = Graph(context: harness.context)
        let feedback = StreamFeedbackNode(context: harness.context, strategy: PortType.Float)
        (feedback.findPort(named: "inputInitial") as NodePort<GPUStream<Float>>?)?.value = try stream([0], harness)
        feedback.inputReset.value = true
        let increment = StreamMathNode(context: harness.context, strategy: PortType.Float)
        (increment.findPort(named: "inputBValue") as ParameterPort<Float>?)?.value = 1
        graph.addNode(feedback)
        graph.addNode(increment)
        graph.connect(feedback.port(named: "outputStream"), to: increment.port(named: "inputA"))
        graph.connect(increment.port(named: "outputStream"), to: feedback.port(named: "inputStream"))
        _ = readback(increment.port(named: "outputStream"), as: Float.self, type: .Float, in: graph, harness)
        let output = try #require(increment.findPort(named: "outputStream") as NodePort<GPUStream<Float>>?)

        var attributes: [PublishedAttribute?] = []
        try run(graph, frames: 3, harness) { _ in attributes.append(output.value?.attribute) }
        #expect(attributes.count == 3 && attributes.allSatisfy { $0 != nil })
        #expect(attributes[1] === attributes[0] && attributes[2] === attributes[0])
    }
}
