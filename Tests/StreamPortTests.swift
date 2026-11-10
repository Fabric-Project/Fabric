import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

@Suite("Stream port")
struct StreamPortTests
{
    private func makeContext() -> Context?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    private func positions(_ context: Context, count: Int = 3) throws -> PublishedAttribute
    {
        let values = ContiguousArray((0..<count).map { simd_float3(Float($0), 0, 0) })
        return try PublishedAttribute.publishing(values, scalar: .float32, components: 3, allocator: context.gpuAllocator)
    }

    private func roundTrip<N: Node>(_ node: N, context: Context) throws -> N
    {
        let data = try JSONEncoder().encode(node)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        return try decoder.decode(N.self, from: data)
    }

    // MARK: - Type

    @Test("Every stream type round-trips through its name and maps to its GPUStream type")
    func streamTypeNamesRoundTrip()
    {
        let expected: [(PortType, String, Any.Type)] = [
            (.Stream(elementType: .Float), "Stream of Float", GPUStream<Float>.self),
            (.Stream(elementType: .Int), "Stream of Int", GPUStream<Int>.self),
            (.Stream(elementType: .Vector2), "Stream of Vector 2", GPUStream<simd_float2>.self),
            (.Stream(elementType: .Vector3), "Stream of Vector 3", GPUStream<simd_float3>.self),
            (.Stream(elementType: .Vector4), "Stream of Vector 4", GPUStream<simd_float4>.self),
            (.Stream(elementType: .Quaternion), "Stream of Quaternion", GPUStream<simd_quatf>.self),
        ]
        for (type, name, valueType) in expected
        {
            #expect(type.rawValue == name)
            #expect(PortType(rawValue: name) == type)
            #expect(type.type == valueType)
            #expect(PortType.allCases.contains(type))
        }
    }

    @Test("A stream of an element it can't carry is not a port type")
    func unsupportedStreamNamesDoNotParse()
    {
        #expect(PortType(rawValue: "Stream of Bool") == nil)
        #expect(PortType(rawValue: "Stream of Color") == nil)
        #expect(PortType(rawValue: "Stream of Transform") == nil)
        #expect(PortType(rawValue: "Stream of Stream of Float") == nil)
    }

    @Test("Streams connect only to the same element type, or to Virtual")
    func streamsConnectOnlyToTheirOwnElementType()
    {
        let vector3 = PortType.Stream(elementType: .Vector3)
        #expect(vector3.canConnect(to: .Stream(elementType: .Vector3)))
        #expect(!vector3.canConnect(to: .Stream(elementType: .Float)))
        #expect(!vector3.canConnect(to: .Stream(elementType: .Vector4)))
        #expect(!vector3.canConnect(to: .Vector3))
        #expect(!vector3.canConnect(to: .Array(portType: .Vector3)))
        #expect(!vector3.canConnect(to: .Array(portType: .Virtual)))
        #expect(!vector3.canConnect(to: .NumericVirtual))
        #expect(vector3.canConnect(to: .Virtual))
        #expect(!PortType.Stream(elementType: .Vector4).canConnect(to: .Stream(elementType: .Quaternion)))
        #expect(!PortType.Stream(elementType: .Int).canConnect(to: .Stream(elementType: .Float)))
    }

    // MARK: - Value

    @Test("A stream takes only the layouts its element allows")
    func streamValidatesLayout() throws
    {
        guard let context = makeContext() else { return }
        let float3 = try positions(context)
        #expect(try GPUStream<simd_float3>(attribute: float3).count == .known(3))
        #expect(throws: GPUStreamError.layoutDoesNotMatchElement(.Vector4)) { try GPUStream<simd_float4>(attribute: float3) }

        let halves = ContiguousArray<SIMD4<UInt16>>(repeating: .zero, count: 2)
        let half3 = try PublishedAttribute.publishing(halves, scalar: .float16, components: 3, allocator: context.gpuAllocator)
        #expect(try GPUStream<simd_float3>(attribute: half3).attribute === half3)

        let floats = try PublishedAttribute.publishing(ContiguousArray<Float>([1, 2]), scalar: .float32, components: 1, allocator: context.gpuAllocator)
        #expect(throws: GPUStreamError.layoutDoesNotMatchElement(.Int)) { try GPUStream<Int>(attribute: floats) }

        let ints = try PublishedAttribute.publishing(ContiguousArray<Int32>([1, 2]), scalar: .int32, components: 1, allocator: context.gpuAllocator)
        #expect(try GPUStream<Int>(attribute: ints).count == .known(2))
    }

    @Test("A stream's count can't exceed what its attribute holds")
    func streamCountIsBounded() throws
    {
        guard let context = makeContext() else { return }
        let float3 = try positions(context, count: 3)
        let countBuffer = try #require(context.device.makeBuffer(length: 16))

        #expect(try GPUStream<simd_float3>(attribute: float3, count: .known(2)).count.capacity == 2)
        #expect(throws: GPUStreamError.countExceedsAttribute) { try GPUStream<simd_float3>(attribute: float3, count: .known(4)) }
        #expect(throws: GPUStreamError.countExceedsAttribute) { try GPUStream<simd_float3>(attribute: float3, count: .known(-1)) }
        #expect(try GPUStream<simd_float3>(attribute: float3, count: .gpu(try PointsDrawArguments(buffer: countBuffer, offset: 0), capacity: 3)).count.capacity == 3)
        #expect(throws: GPUStreamError.countExceedsAttribute) {
            try GPUStream<simd_float3>(attribute: float3, count: .gpu(try PointsDrawArguments(buffer: countBuffer, offset: 0), capacity: 4))
        }
    }

    @Test("GPU counts are the same count only at the same buffer and offset")
    func gpuCountIdentity() throws
    {
        guard let context = makeContext() else { return }
        let first = try #require(context.device.makeBuffer(length: 32))
        let second = try #require(context.device.makeBuffer(length: 32))
        let record = GPUStreamCount.gpu(try PointsDrawArguments(buffer: first, offset: 0), capacity: 3)

        #expect(record == .gpu(try PointsDrawArguments(buffer: first, offset: 0), capacity: 3))
        #expect(record != .gpu(try PointsDrawArguments(buffer: first, offset: 16), capacity: 3))
        #expect(record != .gpu(try PointsDrawArguments(buffer: second, offset: 0), capacity: 3))
        #expect(record != .known(3))
        // A record that doesn't lie wholly inside its buffer can't be made.
        #expect(throws: PointsError.drawArgumentsOutOfRange) { try PointsDrawArguments(buffer: first, offset: 24) }
        #expect(throws: PointsError.drawArgumentsOutOfRange) { try PointsDrawArguments(buffer: first, offset: 2) }
    }

    @Test("A stream round-trips through a boxed port value, and only into its own element type")
    func boxedValueRoundTrips() throws
    {
        guard let context = makeContext() else { return }
        let stream = try GPUStream<simd_float3>(attribute: try positions(context))

        let boxed = stream.toPortValue()
        #expect(GPUStream<simd_float3>.fromPortValue(boxed) == stream)
        #expect(GPUStream<simd_float4>.fromPortValue(boxed) == nil)
        #expect(GPUStream<simd_float3>.fromPortValue(.Float(1)) == nil)

        // The same bytes published again are a different stream.
        let republished = try GPUStream<simd_float3>(attribute: try positions(context))
        #expect(republished != stream)
    }

    // MARK: - Ports

    @Test("Every stream type makes a typed port that saves and opens as the same type and id")
    func streamPortsSaveAndOpen() throws
    {
        guard let context = makeContext() else { return }
        for elementType in PortType.streamElementTypes
        {
            let type = PortType.Stream(elementType: elementType)
            let port = type.makeFreshPort(name: "Stream", kind: .Inlet)
            #expect(port.portType == type)
            #expect(port.parameter == nil)

            let data = try JSONEncoder().encode(AnyPort(port))
            let decoder = JSONDecoder()
            decoder.context = DecoderContext(documentContext: context)
            let decoded = try decoder.decode(AnyPort.self, from: data).base
            #expect(decoded.portType == type)
            #expect(decoded.id == port.id)
        }
    }

    @Test("A stream port sends its value to a connected stream port of the same type")
    func streamPortsConnect() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let source = PassThroughNode<GPUStream<simd_float3>>(context: context)
        let target = PassThroughNode<GPUStream<simd_float3>>(context: context)
        graph.addNode(source)
        graph.addNode(target)
        graph.connect(source.output, to: target.input)

        let stream = try GPUStream<simd_float3>(attribute: try positions(context))
        source.output.send(stream)
        #expect(target.input.value == stream)
    }

    @Test("A published stream port gets a typed proxy on its subgraph")
    func publishedStreamGetsProxy() throws
    {
        guard let context = makeContext() else { return }
        let inner = Graph(context: context)
        let passThrough = PassThroughNode<GPUStream<simd_float3>>(context: context)
        inner.addNode(passThrough)
        passThrough.output.published = true
        inner.rebuildPublishedParameterGroup()

        let subgraph = SubgraphNode(context: context, subGraph: inner)
        subgraph.rebuildProxyPorts()
        let proxy = try #require(subgraph.ports.first { $0 is ProxyPort<GPUStream<simd_float3>> })
        #expect(proxy.portType == .Stream(elementType: .Vector3))
    }

    @Test("Queue set to a stream type queues streams, and keeps its typed ports through a save")
    func queueCarriesStreams() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let context = harness.context
        let type = PortType.Stream(elementType: .Vector3)
        #expect(ArrayQueueNode.strategyOptions.contains { ($0 as? PortType) == type })

        let node = ArrayQueueNode(context: context, settings: StrategyNodeSettings(strategy: type.rawValue))
        node.inputSizeParam.value = 2
        let input = try #require(node.findPort(named: "inputPort") as NodePort<GPUStream<simd_float3>>?)
        let output = try #require(node.findPort(named: "outputPort") as Fabric.Port?)
        #expect(output.portType == .Array(portType: type))

        let first = try GPUStream<simd_float3>(attribute: try positions(context))
        let second = try GPUStream<simd_float3>(attribute: try positions(context))
        input.value = first
        try harness.execute(node)
        input.value = second
        try harness.execute(node)
        #expect(output.snapshotValue() == .Array([second.toPortValue(), first.toPortValue()]))

        let reopened = try roundTrip(node, context: context)
        #expect((reopened.findPort(named: "inputPort") as NodePort<GPUStream<simd_float3>>?)?.id == input.id)
        #expect((reopened.findPort(named: "outputPort") as Fabric.Port?)?.portType == .Array(portType: type))
    }

    @Test("Sample and Hold set to a stream type builds stream ports and keeps them through a save")
    func sampleAndHoldCarriesStreams() throws
    {
        guard let context = makeContext() else { return }
        let type = PortType.Stream(elementType: .Vector3)
        #expect(SampleAndHoldNode.strategyOptions.contains { ($0 as? PortType) == type })

        let node = SampleAndHoldNode(context: context, settings: StrategyNodeSettings(strategy: type.rawValue))
        let input = try #require(node.findPort(named: "inputValue") as NodePort<GPUStream<simd_float3>>?)
        let output = try #require(node.findPort(named: "outputValue") as NodePort<GPUStream<simd_float3>>?)

        let reopened = try roundTrip(node, context: context)
        #expect(reopened.strategyName == type.rawValue)
        #expect((reopened.findPort(named: "inputValue") as NodePort<GPUStream<simd_float3>>?)?.id == input.id)
        #expect((reopened.findPort(named: "outputValue") as NodePort<GPUStream<simd_float3>>?)?.id == output.id)
    }
}
