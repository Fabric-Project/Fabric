import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

@Suite("Stream Compute, Points Compute stream inputs and Image to Stream", .serialized)
struct StreamComputeTests
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
    }

    private func runFrame(_ graph: Graph, _ harness: GraphExecutionTestHarness) throws
    {
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }
        let commands = try #require(renderer.makeCommandBuffer())
        try renderer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: 0),
                             renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
        commands.commit()
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)
    }

    /// `outlet` read back on the CPU after one frame, through Stream to Array.
    private func readBack<Element: GPUStreamElement>(_ outlet: Fabric.Port, as _: Element.Type, type: PortType,
                                                     in graph: Graph, _ harness: GraphExecutionTestHarness) throws -> ContiguousArray<Element>?
    {
        let readback = StreamToArrayNode(context: harness.context, strategy: type)
        let consumer = PullingConsumer(context: harness.context)
        graph.addNode(readback)
        graph.addNode(consumer)
        graph.connect(outlet, to: readback.port(named: "inputStream"))
        graph.connect(readback.port(named: "outputArray"), to: consumer.input)
        try runFrame(graph, harness)
        return (readback.findPort(named: "outputArray") as NodePort<ContiguousArray<Element>>?)?.value
    }

    private func stream<Element: GPUStreamElement>(_ values: ContiguousArray<Element>, _ harness: GraphExecutionTestHarness) throws -> GPUStream<Element>
    {
        try GPUStream(attribute: try Element.publishStream(values, allocator: harness.context.gpuAllocator).attribute)
    }

    private static let doubling = StreamComputeSettings(
        inputs: [StreamKernelField(name: "source", elementType: .Float)],
        outputs: [StreamKernelField(name: "doubled", elementType: .Float), StreamKernelField(name: "index", elementType: .Int)],
        countSource: "source",
        kernelSource: """
        void streamCompute(uint id, constant StreamComputeUniforms &uniforms, thread const StreamComputeInputs &inputs, thread StreamComputeOutput &out)
        {
            out.doubled = 2.0 * inputs.source.read(id);
            out.index = int(id);
        }
        """)

    @Test("Settings make a port for each stream input and output, in order")
    func settingsShapeThePorts() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let node = StreamComputeNode(context: harness.context, settings: Self.doubling)
        #expect(node.ports.map(\.name) == ["Count", "Parameters", "Every Frame", "source", "doubled", "index"])
        #expect((node.findPort(named: "inputStream.source.Float") as NodePort<GPUStream<Float>>?) != nil)
        #expect((node.findPort(named: "outputStream.index.Int") as NodePort<GPUStream<Int>>?) != nil)

        // A count source that isn't an input falls back to the Count input.
        var settings = Self.doubling
        settings.countSource = "missing"
        #expect(settings.normalized().countSource == "")
    }

    @Test("Stream Compute reads a stream, writes Float and Int streams, and takes the input's count")
    func computesFromAnInput() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let graph = Graph(context: harness.context)
        let compute = StreamComputeNode(context: harness.context, settings: Self.doubling)
        compute.inputEveryFrame.value = false
        graph.addNode(compute)
        let input = try #require(compute.findPort(named: "inputStream.source.Float") as NodePort<GPUStream<Float>>?)
        input.value = try stream(ContiguousArray<Float>([1, 2.5, -3]), harness)

        let doubled = try readBack(compute.port(named: "outputStream.doubled.Float"), as: Float.self, type: .Float, in: graph, harness)
        #expect(doubled == [2, 5, -6])
        let index = try #require(compute.findPort(named: "outputStream.index.Int") as NodePort<GPUStream<Int>>?)
        #expect(index.value?.count == .known(3))
        #expect(compute.status == nil)
    }

    @Test("Stream Compute decodes half-precision input")
    func readsHalfInput() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let graph = Graph(context: harness.context)
        let compute = StreamComputeNode(context: harness.context, settings: Self.doubling)
        graph.addNode(compute)
        // 1 and -2.5 as halves.
        let halves = try PublishedAttribute.publishing(ContiguousArray<UInt16>([0x3C00, 0xC100]), scalar: .float16, components: 1,
                                                       allocator: harness.context.gpuAllocator)
        let input = try #require(compute.findPort(named: "inputStream.source.Float") as NodePort<GPUStream<Float>>?)
        input.value = try GPUStream(attribute: halves)

        #expect(try readBack(compute.port(named: "outputStream.doubled.Float"), as: Float.self, type: .Float, in: graph, harness) == [2, -5])
    }

    @Test("A counted input's GPU count travels to the outputs, and limits what is written")
    func gpuCountTravels() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let arguments = try #require(harness.context.device.makeBuffer(length: 16, options: .storageModeShared))
        arguments.contents().storeBytes(of: MTLDrawPrimitivesIndirectArguments(vertexCount: 2, instanceCount: 1, vertexStart: 0, baseInstance: 0),
                                        as: MTLDrawPrimitivesIndirectArguments.self)
        let whole = try stream(ContiguousArray<Float>([1, 2, 3, 4]), harness)
        let counted = try GPUStream<Float>(attribute: whole.attribute, count: .gpu(try PointsDrawArguments(buffer: arguments, offset: 0), capacity: 4))

        let graph = Graph(context: harness.context)
        let compute = StreamComputeNode(context: harness.context, settings: Self.doubling)
        graph.addNode(compute)
        let input = try #require(compute.findPort(named: "inputStream.source.Float") as NodePort<GPUStream<Float>>?)
        input.value = counted

        #expect(try readBack(compute.port(named: "outputStream.doubled.Float"), as: Float.self, type: .Float, in: graph, harness) == [2, 4])
        let output = try #require(compute.findPort(named: "outputStream.doubled.Float") as NodePort<GPUStream<Float>>?)
        #expect(output.value?.count == counted.count)
    }

    @Test("Without a count source, Count sets the length and an unwired input reads zero")
    func countInputAndMissingInput() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        var settings = Self.doubling
        settings.countSource = ""
        let graph = Graph(context: harness.context)
        let compute = StreamComputeNode(context: harness.context, settings: settings)
        compute.inputCount.value = 3
        graph.addNode(compute)

        #expect(try readBack(compute.port(named: "outputStream.doubled.Float"), as: Float.self, type: .Float, in: graph, harness) == [0, 0, 0])
    }

    @Test("A function that doesn't compile is the node's status, and writes nothing")
    func failingFunctionIsTheStatus() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        var settings = Self.doubling
        settings.kernelSource = "void streamCompute(uint id, constant StreamComputeUniforms &uniforms, thread const StreamComputeInputs &inputs, thread StreamComputeOutput &out) { out.nope = 1; }"
        let graph = Graph(context: harness.context)
        let compute = StreamComputeNode(context: harness.context, settings: settings)
        graph.addNode(compute)
        let input = try #require(compute.findPort(named: "inputStream.source.Float") as NodePort<GPUStream<Float>>?)
        input.value = try stream(ContiguousArray<Float>([1]), harness)

        #expect(try readBack(compute.port(named: "outputStream.doubled.Float"), as: Float.self, type: .Float, in: graph, harness) == nil)
        if case .error = compute.status {} else { Issue.record("The compile error is the node's status") }
    }

    @Test("Points Compute reads a stream input and takes its count")
    func pointsComputeReadsStreams() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let settings = PointsComputeSettings(
            hasNormals: false, hasColors: false, hasSizes: false, hasTexcoords: false, customAttributes: [],
            streamInputs: [StreamKernelField(name: "seed", elementType: .Vector3)], countSource: "seed",
            kernelSource: """
            void pointsCompute(uint id, constant PointsComputeUniforms &uniforms, thread const PointsComputeInputs &inputs, thread PointsComputeOutput &point)
            {
                point.position = inputs.seed.read(id) + float3(0.0, 1.0, 0.0);
            }
            """)
        let graph = Graph(context: harness.context)
        let compute = PointsComputeNode(context: harness.context, settings: settings)
        #expect(compute.ports.map(\.name) == ["Count", "Parameters", "seed", "Points"])
        let input = try #require(compute.findPort(named: "inputStream.seed.Vector 3") as NodePort<GPUStream<simd_float3>>?)
        input.value = try stream(ContiguousArray([simd_float3(1, 0, 0), simd_float3(2, 0, 0)]), harness)

        let split = PointsToStreamsNode(context: harness.context)
        graph.addNode(compute)
        graph.addNode(split)
        graph.connect(compute.outputPoints, to: split.inputPoints)

        let positions = try readBack(split.outputPositions, as: simd_float3.self, type: .Vector3, in: graph, harness)
        #expect(positions == [simd_float3(1, 1, 0), simd_float3(2, 1, 0)])
        #expect(compute.status == nil)
    }

    @Test("Image to Stream gives each sampled pixel's color and texture coordinate, in rows from the top left")
    func imageBecomesStreams() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: 2, height: 2, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = try #require(harness.context.device.makeTexture(descriptor: descriptor))
        let pixels: [simd_float4] = [[1, 0, 0, 1], [0, 1, 0, 1], [0, 0, 1, 1], [1, 1, 1, 1]]
        pixels.withUnsafeBytes { bytes in
            if let address = bytes.baseAddress
            {
                texture.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, withBytes: address, bytesPerRow: 2 * MemoryLayout<simd_float4>.stride)
            }
        }

        let graph = Graph(context: harness.context)
        let image = ImageToStreamNode(context: harness.context)
        image.inputImage.value = .unmanaged(texture: texture)
        graph.addNode(image)

        let colors = try readBack(image.outputColors, as: simd_float4.self, type: .Vector4, in: graph, harness)
        #expect(colors == ContiguousArray(pixels))
        #expect(image.outputCount.value == 4)

        let texcoords = try #require(image.outputTexcoords.value)
        #expect(texcoords.count == .known(4))
    }

    /// A shared `rgba32Float` texture `width` by `height` holding `pixels` in rows.
    private func texture(_ pixels: [simd_float4], width: Int, height: Int, _ harness: GraphExecutionTestHarness) throws -> MTLTexture
    {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = try #require(harness.context.device.makeTexture(descriptor: descriptor))
        pixels.withUnsafeBytes { bytes in
            if let address = bytes.baseAddress
            {
                texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: address,
                                bytesPerRow: width * MemoryLayout<simd_float4>.stride)
            }
        }
        return texture
    }

    @Test("Image to Stream samples the image as presented: flipped and rotated images read in their presented order")
    func imageToStreamFollowsPresentation() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }
        let red: simd_float4 = [1, 0, 0, 1], green: simd_float4 = [0, 1, 0, 1], blue: simd_float4 = [0, 0, 1, 1], white: simd_float4 = [1, 1, 1, 1]

        // Flipped across: each presented row is its stored row reversed.
        let flipped = FabricImage.unmanaged(texture: try texture([red, green, blue, white], width: 2, height: 2, harness))
        flipped.textureTransform = simd_float4x4(simd_float4(-1, 0, 0, 0), simd_float4(0, 1, 0, 0), simd_float4(0, 0, 1, 0), simd_float4(1, 0, 0, 1))
        let flipGraph = Graph(context: harness.context)
        let flipNode = ImageToStreamNode(context: harness.context)
        flipNode.inputImage.value = flipped
        flipGraph.addNode(flipNode)
        #expect(try readBack(flipNode.outputColors, as: simd_float4.self, type: .Vector4, in: flipGraph, harness) == [green, red, white, blue])

        // A quarter turn: stored 2 across and 1 down is presented 1 across and 2 down.
        let turned = FabricImage.unmanaged(texture: try texture([red, green], width: 2, height: 1, harness))
        turned.textureTransform = simd_float4x4(simd_float4(0, -1, 0, 0), simd_float4(1, 0, 0, 0), simd_float4(0, 0, 1, 0), simd_float4(0, 1, 0, 1))
        let turnGraph = Graph(context: harness.context)
        let turnNode = ImageToStreamNode(context: harness.context)
        turnNode.inputImage.value = turned
        turnGraph.addNode(turnNode)
        #expect(try readBack(turnNode.outputColors, as: simd_float4.self, type: .Vector4, in: turnGraph, harness) == [red, green])
        #expect(turnNode.outputCount.value == 2)
        // One column of two rows, so both samples sit at the middle across.
        let turnTexcoordGraph = Graph(context: harness.context)
        let turnTexcoordNode = ImageToStreamNode(context: harness.context)
        turnTexcoordNode.inputImage.value = turned
        turnTexcoordGraph.addNode(turnTexcoordNode)
        #expect(try readBack(turnTexcoordNode.outputTexcoords, as: simd_float2.self, type: .Vector2, in: turnTexcoordGraph, harness) == [[0.5, 0.25], [0.5, 0.75]])
    }
}
