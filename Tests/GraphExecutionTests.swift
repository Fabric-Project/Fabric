import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

private struct GraphExecutionTestHarness {
    let context: Context
    let renderer: GraphRenderer
    let renderWidth: Int
    let renderHeight: Int

    init?(renderWidth: Int = 320, renderHeight: Int = 180) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }

        self.context = Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
        self.renderer = GraphRenderer(context: self.context)
        self.renderWidth = renderWidth
        self.renderHeight = renderHeight
        self.renderer.resize(
            size: (width: Float(renderWidth), height: Float(renderHeight)),
            scaleFactor: 1.0
        )
    }

    func makeExecutionContext(
        time: TimeInterval,
        deltaTime: TimeInterval,
        systemTime: TimeInterval? = nil,
        frameNumber: Int
    ) -> GraphExecutionInfo {
        GraphExecutionInfo(
            timing: GraphExecutionTiming(
                time: time,
                deltaTime: deltaTime,
                displayTime: time,
                systemTime: systemTime ?? time,
                frameNumber: frameNumber
            ),
            iterationInfo: nil,
            eventInfo: nil
        )
    }

    func makeTexture(
        width: Int = 32,
        height: Int = 32,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]

        guard let texture = self.context.device.makeTexture(descriptor: descriptor) else {
            throw TestFailure("Failed to create test texture")
        }

        return texture
    }

    func makeImage(
        width: Int = 32,
        height: Int = 32,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) throws -> FabricImage {
        FabricImage.unmanaged(texture: try self.makeTexture(width: width, height: height, pixelFormat: pixelFormat))
    }

    func render(graph: Graph, executionInfo: GraphExecutionInfo, drawScene: Bool = true) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: self.context.colorPixelFormat,
            width: self.renderWidth,
            height: self.renderHeight,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]

        guard let colorTexture = self.context.device.makeTexture(descriptor: descriptor) else {
            throw TestFailure("Failed to create color render target")
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = colorTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = self.renderer.commandQueue.makeCommandBuffer() else {
            throw TestFailure("Failed to create command buffer")
        }

        if drawScene {
            self.renderer.executeAndDraw(
                graph: graph,
                executionInfo: executionInfo,
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer
            )
        } else {
            self.renderer.execute(
                graph: graph,
                executionInfo: executionInfo,
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer
            )
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw error
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private func publish(_ port: Fabric.Port, in graph: Graph) {
    port.published = true
    graph.rebuildPublishedParameterGroup()
}

private func floatPort(named name: String, kind: PortKind, on node: Node) throws -> NodePort<Float> {
    guard let port = node.ports.first(where: { $0.name == name && $0.kind == kind }) as? NodePort<Float> else {
        throw TestFailure("Missing Float port named \(name)")
    }

    return port
}

private func intPort(named name: String, kind: PortKind, on node: Node) throws -> NodePort<Int> {
    guard let port = node.ports.first(where: { $0.name == name && $0.kind == kind }) as? NodePort<Int> else {
        throw TestFailure("Missing Int port named \(name)")
    }

    return port
}

private func imagePort(named name: String, kind: PortKind, on node: Node) throws -> NodePort<FabricImage> {
    guard let port = node.ports.first(where: { $0.name == name && $0.kind == kind }) as? NodePort<FabricImage> else {
        throw TestFailure("Missing FabricImage port named \(name)")
    }

    return port
}

private final class RecursiveArrayDictionaryPortNode: Node {
    override class var name: String { "Recursive Array Dictionary Port" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Test node for recursive collection port publishing." }

    static let recursivePortType: PortType = .Array(portType: .Dictionary(valueType: .Array(portType: .Float)))

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)] {
        super.registerPorts(context: context) + [
            ("output", recursivePortType.makeFreshPort(name: "Recursive", kind: .Outlet)),
        ]
    }

    required init(context: Context) {
        super.init(context: context)
    }

    required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
    }
}

private func requireValue<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw TestFailure(message)
    }

    return value
}

private func expectEqual(_ lhs: Float?, _ rhs: Float, tolerance: Float = 0.0001) throws {
    let lhs = try requireValue(lhs, "Expected Float value")
    #expect(abs(lhs - rhs) <= tolerance)
}

private func expectEqual(_ lhs: simd_float3, _ rhs: simd_float3, tolerance: Float = 0.0001) {
    #expect(abs(lhs.x - rhs.x) <= tolerance)
    #expect(abs(lhs.y - rhs.y) <= tolerance)
    #expect(abs(lhs.z - rhs.z) <= tolerance)
}

private func expectEqual(_ lhs: simd_float3x3, _ rhs: simd_float3x3, tolerance: Float = 0.0001) {
    expectEqual(lhs.columns.0, rhs.columns.0, tolerance: tolerance)
    expectEqual(lhs.columns.1, rhs.columns.1, tolerance: tolerance)
    expectEqual(lhs.columns.2, rhs.columns.2, tolerance: tolerance)
}

private func roundTripGraphToTemporaryFile(_ graph: Graph, context: Context) throws -> Graph {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let data = try encoder.encode(graph)
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("fabric-graph-roundtrip-\(UUID().uuidString)")
        .appendingPathExtension("json")

    try data.write(to: fileURL)
    let loadedData = try Data(contentsOf: fileURL)

    let decoder = JSONDecoder()
    decoder.context = DecoderContext(documentContext: context)

    return try decoder.decode(Graph.self, from: loadedData)
}

@Suite("Graph Execution")
struct GraphExecutionTests {

    @Test("Number node outputs configured value after one render")
    func numberNodeOutputsConfiguredValue() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let numberNode = PassThroughNode<Float>(context: harness.context)
        numberNode.input.value = 3.5
        graph.addNode(numberNode)
        publish(numberNode.output, in: graph)

        let context = harness.makeExecutionContext(time: 10, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: context)
        harness.renderer.stopExecution(graph: graph)

        try expectEqual(numberNode.output.value, 3.5)
    }

    @Test("Connected number nodes feed Number Binary Operator add")
    func connectedNumberNodesComputeSum() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let left = PassThroughNode<Float>(context: harness.context)
        let right = PassThroughNode<Float>(context: harness.context)
        let addNode = NumberBinaryOperator(context: harness.context)

        left.input.value = 2.25
        right.input.value = 4.75
        addNode.inputParam.value = "Add"

        graph.addNode(left)
        graph.addNode(right)
        graph.addNode(addNode)

        left.output.connect(to: addNode.inputNumber1)
        right.output.connect(to: addNode.inputNumber2)
        publish(addNode.outputNumber, in: graph)

        let context = harness.makeExecutionContext(time: 20, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: context)
        harness.renderer.stopExecution(graph: graph)

        try expectEqual(addNode.outputNumber.value, 7.0)
    }

    @Test("Updating an upstream number recomputes the downstream output")
    func downstreamOutputUpdatesAfterInputChange() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let left = PassThroughNode<Float>(context: harness.context)
        let right = PassThroughNode<Float>(context: harness.context)
        let addNode = NumberBinaryOperator(context: harness.context)

        left.input.value = 1
        right.input.value = 2
        addNode.inputParam.value = "Add"

        graph.addNode(left)
        graph.addNode(right)
        graph.addNode(addNode)

        left.output.connect(to: addNode.inputNumber1)
        right.output.connect(to: addNode.inputNumber2)
        publish(addNode.outputNumber, in: graph)

        let firstContext = harness.makeExecutionContext(time: 30, deltaTime: 0, frameNumber: 0)
        let secondContext = harness.makeExecutionContext(time: 31, deltaTime: 1, frameNumber: 1)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: firstContext)
        try expectEqual(addNode.outputNumber.value, 3)

        right.input.value = 9
        try harness.render(graph: graph, executionInfo: secondContext)
        harness.renderer.stopExecution(graph: graph)

        try expectEqual(addNode.outputNumber.value, 10)
    }

    @Test("Current time node advances relative to graph start")
    func currentTimeNodeUsesGraphTiming() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let timeNode = CurrentTimeNode(context: harness.context)
        graph.addNode(timeNode)
        publish(timeNode.outputNumber, in: graph)

        let firstContext = harness.makeExecutionContext(time: 100, deltaTime: 0, systemTime: 200, frameNumber: 0)
        let secondContext = harness.makeExecutionContext(time: 101.25, deltaTime: 1.25, systemTime: 201, frameNumber: 1)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: firstContext)
        try expectEqual(timeNode.outputNumber.value, 0)

        try harness.render(graph: graph, executionInfo: secondContext)
        harness.renderer.stopExecution(graph: graph)

        try expectEqual(timeNode.outputNumber.value, 1.25)
    }

    @Test("System time node advances relative to execution start")
    func systemTimeNodeUsesSystemTiming() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let timeNode = SystemTimeNode(context: harness.context)
        graph.addNode(timeNode)
        publish(timeNode.outputNumber, in: graph)

        let firstContext = harness.makeExecutionContext(time: 100, deltaTime: 0, systemTime: 500, frameNumber: 0)
        let secondContext = harness.makeExecutionContext(time: 101, deltaTime: 1, systemTime: 502.5, frameNumber: 1)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: firstContext)
        try expectEqual(timeNode.outputNumber.value, 0)

        try harness.render(graph: graph, executionInfo: secondContext)
        harness.renderer.stopExecution(graph: graph)

        try expectEqual(timeNode.outputNumber.value, 2.5)
    }

    @Test("Spot light node applies spotlight and shadow parameters")
    func spotLightNodeAppliesSpotlightAndShadowParameters() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let node = SpotLightNode(context: harness.context)
        node.inputColor.value = simd_float3(0.25, 0.5, 0.75)
        node.inputIntensity.value = 42.0
        node.inputRadius.value = 18.0
        node.inputAngleInner.value = 40.0
        node.inputAngleOuter.value = 30.0
        node.inputLookAt.value = simd_float3(0.0, -1.0, 0.0)
        node.inputShadowStrength.value = 1.5
        node.inputShadowRadius.value = 3.25
        node.inputShadowBias.value = 0.0025
        graph.addNode(node)

        let executionContext = harness.makeExecutionContext(time: 1.0, deltaTime: 0.0, frameNumber: 0)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: executionContext, drawScene: false)
        harness.renderer.stopExecution(graph: graph)

        guard let light = node.getObject() as? SpotLight else {
            throw TestFailure("Spot light node did not vend a SpotLight object")
        }

        expectEqual(light.color, simd_float3(0.25, 0.5, 0.75))
        #expect(abs(light.intensity - 42.0) <= 0.0001)
        #expect(abs(light.radius - 18.0) <= 0.0001)
        #expect(abs(light.angleInner - 40.0) <= 0.0001)
        #expect(abs(light.angleOuter - 40.0) <= 0.0001)
        #expect(abs(light.shadow.strength - 1.5) <= 0.0001)
        #expect(abs(light.shadow.radius - 3.25) <= 0.0001)
        #expect(abs(light.shadow.bias - 0.0025) <= 0.0001)
        #expect(light.castShadow)
    }

    @Test("Spot light node supports projector image mode and flipped textures")
    func spotLightNodeSupportsProjectorImages() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let node = SpotLightNode(context: harness.context)
        node.inputProjectionMode.value = "Color"

        let texture = try harness.makeTexture(width: 16, height: 8)
        let image = FabricImage.unmanaged(texture: texture)
        image.isFlipped = true
        node.inputProjectionImage.value = image
        graph.addNode(node)

        let executionContext = harness.makeExecutionContext(time: 2.0, deltaTime: 0.0, frameNumber: 0)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: executionContext, drawScene: false)
        harness.renderer.stopExecution(graph: graph)

        guard let light = node.getObject() as? SpotLight else {
            throw TestFailure("Spot light node did not vend a SpotLight object")
        }

        #expect(light.projectionTexture === texture)
        #expect(light.projectionMode == .color)

        let expectedFlipTransform = simd_float3x3(
            simd_float3(1.0, 0.0, 0.0),
            simd_float3(0.0, -1.0, 0.0),
            simd_float3(0.0, 1.0, 1.0)
        )
        expectEqual(light.projectionTransform, expectedFlipTransform)
    }

    @Test("Spot light node is registered in the node registry")
    func spotLightNodeIsRegistered() {
        let nodeClass = NodeRegistry.shared.nodeClass(for: String(describing: SpotLightNode.self))
        #expect(nodeClass == SpotLightNode.self)
    }

    @Test("Depth of field node renders an output image from color and depth inputs")
    func depthOfFieldNodeRendersOutputImage() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let node = DepthOfFieldNode(context: harness.context)
        node.inputImage.value = try harness.makeImage(width: 48, height: 32, pixelFormat: harness.context.colorPixelFormat)
        node.inputDepthImage.value = try harness.makeImage(width: 48, height: 32, pixelFormat: harness.context.depthPixelFormat)
        graph.addNode(node)
        publish(node.outputImage, in: graph)

        let executionContext = harness.makeExecutionContext(time: 0, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: executionContext, drawScene: false)
        harness.renderer.stopExecution(graph: graph)

        let outputImage = try requireValue(node.outputImage.value, "Expected depth-of-field output image")
        #expect(outputImage.texture.width == 48)
        #expect(outputImage.texture.height == 32)
    }

    @Test("Post process motion blur node renders an output image from color and velocity inputs")
    func postProcessMotionBlurNodeRendersOutputImage() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let node = PostProcessMotionBlurNode(context: harness.context)
        node.inputImage.value = try harness.makeImage(width: 40, height: 24, pixelFormat: harness.context.colorPixelFormat)
        node.inputVelocityImage.value = try harness.makeImage(width: 40, height: 24, pixelFormat: harness.context.velocityPixelFormat)
        graph.addNode(node)
        publish(node.outputImage, in: graph)

        let executionContext = harness.makeExecutionContext(time: 0, deltaTime: 1.0 / 60.0, frameNumber: 0)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: executionContext, drawScene: false)
        harness.renderer.stopExecution(graph: graph)

        let outputImage = try requireValue(node.outputImage.value, "Expected motion-blur output image")
        #expect(outputImage.texture.width == 40)
        #expect(outputImage.texture.height == 24)
    }

    @Test("Depth of field and post process motion blur nodes are registered in the node registry")
    func postProcessBlurNodesAreRegistered() {
        let availableNames = Set(NodeRegistry.shared.availableNodes.map(\.nodeName))
        #expect(availableNames.contains(DepthOfFieldNode.name))
        #expect(availableNames.contains(PostProcessMotionBlurNode.name))
    }

    @Test("Render info reports renderer size and execution count")
    func renderInfoReportsMetrics() throws {
        guard let harness = GraphExecutionTestHarness(renderWidth: 640, renderHeight: 360) else { return }

        let graph = Graph(context: harness.context)
        let renderInfoNode = RenderInfoNode(context: harness.context)
        graph.addNode(renderInfoNode)
        publish(renderInfoNode.outputFrameNumber, in: graph)

        let firstContext = harness.makeExecutionContext(time: 200, deltaTime: 0, frameNumber: 0)
        let secondContext = harness.makeExecutionContext(time: 201, deltaTime: 1, frameNumber: 1)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: firstContext)

        try expectEqual(renderInfoNode.outputWidth.value, 640)
        try expectEqual(renderInfoNode.outputHeight.value, 360)
        #expect(renderInfoNode.outputFrameNumber.value == 0)

        try harness.render(graph: graph, executionInfo: secondContext)
        harness.renderer.stopExecution(graph: graph)

        #expect(renderInfoNode.outputFrameNumber.value == 1)
    }

    @Test("Subgraph proxy inlet and outlet forward values across graphs")
    func subgraphProxyPortsForwardValues() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let source = PassThroughNode<Float>(context: harness.context)
        let subgraphNode = SubgraphNode(context: harness.context)
        let innerAdd = NumberBinaryOperator(context: harness.context)

        source.input.value = 4
        innerAdd.inputNumber2.value = 3
        innerAdd.inputParam.value = "Add"

        graph.addNode(source)
        graph.addNode(subgraphNode)

        subgraphNode.subGraph.addNode(innerAdd)
        innerAdd.inputNumber1.published = true
        innerAdd.outputNumber.published = true
        subgraphNode.subGraph.rebuildPublishedParameterGroup()

        let proxyInput = try floatPort(named: "Number A", kind: .Inlet, on: subgraphNode)
        let proxyOutput = try floatPort(named: "Number", kind: .Outlet, on: subgraphNode)

        source.output.connect(to: proxyInput)
        publish(proxyOutput, in: graph)

        let context = harness.makeExecutionContext(time: 300, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: context)
        harness.renderer.stopExecution(graph: graph)

        try expectEqual(innerAdd.inputNumber1.value, 4)
        try expectEqual(proxyOutput.value, 7)
    }

    @Test("Subgraph proxy preserves recursive array dictionary port type")
    func subgraphProxyPreservesRecursiveArrayDictionaryPortType() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let subgraphNode = SubgraphNode(context: harness.context)
        let innerNode = RecursiveArrayDictionaryPortNode(context: harness.context)

        subgraphNode.subGraph.addNode(innerNode)
        innerNode.port(named: "output").published = true
        subgraphNode.subGraph.rebuildPublishedParameterGroup()

        guard let proxyPort = subgraphNode.ports.first(where: { $0.name == "Recursive" && $0.kind == .Outlet }) else {
            throw TestFailure("Missing recursive collection proxy port")
        }

        #expect(proxyPort.portType == RecursiveArrayDictionaryPortNode.recursivePortType)
    }

    @Test("Iterator node forwards the final iteration info state")
    func iteratorNodePublishesFinalIterationInfo() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let iterator = IteratorNode(context: harness.context)
        let iteratorInfo = IteratorInfoNode(context: harness.context)

        graph.addNode(iterator)
        iterator.subGraph.addNode(iteratorInfo)

        iterator.inputIteratonCount.value = 4

        iteratorInfo.outputIndex.published = true
        iteratorInfo.outputIterationCount.published = true
        iteratorInfo.outputProgress.published = true
        iterator.subGraph.rebuildPublishedParameterGroup()

        let indexProxy = try intPort(named: "Current Iteration", kind: .Outlet, on: iterator)
        let countProxy = try intPort(named: "Number of Iterations", kind: .Outlet, on: iterator)
        let progressProxy = try floatPort(named: "Iterator Progress", kind: .Outlet, on: iterator)

        publish(indexProxy, in: graph)

        let context = harness.makeExecutionContext(time: 400, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: context)
        harness.renderer.stopExecution(graph: graph)

        #expect(indexProxy.value == 3)
        #expect(countProxy.value == 4)
        try expectEqual(progressProxy.value, 1)
    }

    @Test("Deferred subgraph renders color and depth images")
    func deferredSubgraphProducesImages() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let deferred = DeferredSubgraphNode(context: harness.context)

        deferred.inputWidth.value = 64
        deferred.inputHeight.value = 32

        let geometry = BoxGeometryNode(context: harness.context)
        let material = BasicColorMaterialNode(context: harness.context)
        let mesh = MeshNode(context: harness.context)

        deferred.subGraph.addNode(geometry)
        deferred.subGraph.addNode(material)
        deferred.subGraph.addNode(mesh)

        geometry.outputGeometry.connect(to: mesh.inputGeometry)
        material.outputMaterial.connect(to: mesh.inputMaterial)

        graph.addNode(deferred)

        let context = harness.makeExecutionContext(time: 500, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: context)
        harness.renderer.stopExecution(graph: graph)

        let colorImage = try requireValue(deferred.outputColorTexture.value, "Expected deferred color output")
        #expect(colorImage.texture.width == 64)
        #expect(colorImage.texture.height == 32)

        let depthImage = try requireValue(deferred.outputDepthTexture.value, "Expected deferred depth output")
        #expect(depthImage.texture.width == 64)
        #expect(depthImage.texture.height == 32)
    }

    @Test("Deferred subgraph MRT toggle adds and removes auxiliary output ports")
    func deferredSubgraphMRTPortsToggleWithSetting() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let deferred = DeferredSubgraphNode(context: harness.context)
        #expect(deferred.findPort(named: "outputAlbedoTexture", as: Port.self) == nil)
        #expect(deferred.findPort(named: "outputEmissiveTexture", as: Port.self) == nil)

        deferred.deferredMRTEnabled = true

        _ = try imagePort(named: "Albedo Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "Normals Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "PBR Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "Velocity Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "Emissive Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "Color Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "Depth Texture", kind: .Outlet, on: deferred)

        deferred.deferredMRTEnabled = false

        #expect(deferred.findPort(named: "outputAlbedoTexture", as: Port.self) == nil)
        #expect(deferred.findPort(named: "outputNormalsTexture", as: Port.self) == nil)
        #expect(deferred.findPort(named: "outputPBRTexture", as: Port.self) == nil)
        #expect(deferred.findPort(named: "outputVelocityTexture", as: Port.self) == nil)
        #expect(deferred.findPort(named: "outputEmissiveTexture", as: Port.self) == nil)
        _ = try imagePort(named: "Color Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "Depth Texture", kind: .Outlet, on: deferred)
    }

    @Test("Deferred subgraph MRT mode emits auxiliary textures")
    func deferredSubgraphMRTProducesAuxiliaryTextures() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let deferred = DeferredSubgraphNode(context: harness.context)
        deferred.inputWidth.value = 72
        deferred.inputHeight.value = 40
        deferred.deferredMRTEnabled = true

        let geometry = BoxGeometryNode(context: harness.context)
        let material = StandardMaterialNode(context: harness.context)
        let mesh = MeshNode(context: harness.context)

        deferred.subGraph.addNode(geometry)
        deferred.subGraph.addNode(material)
        deferred.subGraph.addNode(mesh)

        geometry.outputGeometry.connect(to: mesh.inputGeometry)
        material.outputMaterial.connect(to: mesh.inputMaterial)

        graph.addNode(deferred)

        let context = harness.makeExecutionContext(time: 550, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: context)
        harness.renderer.stopExecution(graph: graph)

        let albedoImage = try requireValue(imagePort(named: "Albedo Texture", kind: .Outlet, on: deferred).value, "Expected deferred albedo output")
        let normalImage = try requireValue(imagePort(named: "Normals Texture", kind: .Outlet, on: deferred).value, "Expected deferred normals output")
        let pbrImage = try requireValue(imagePort(named: "PBR Texture", kind: .Outlet, on: deferred).value, "Expected deferred PBR output")
        let velocityImage = try requireValue(imagePort(named: "Velocity Texture", kind: .Outlet, on: deferred).value, "Expected deferred velocity output")
        let emissiveImage = try requireValue(imagePort(named: "Emissive Texture", kind: .Outlet, on: deferred).value, "Expected deferred emissive output")

        for image in [albedoImage, normalImage, pbrImage, velocityImage, emissiveImage] {
            #expect(image.texture.width == 72)
            #expect(image.texture.height == 40)
        }
    }

    @Test("Serialized scalar graph decodes and executes like the in-memory graph")
    func serializedScalarGraphRoundTripsAndExecutes() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let left = PassThroughNode<Float>(context: harness.context)
        let right = PassThroughNode<Float>(context: harness.context)
        let addNode = NumberBinaryOperator(context: harness.context)

        left.input.value = 8
        right.input.value = 13
        addNode.inputParam.value = "Add"

        graph.addNode(left)
        graph.addNode(right)
        graph.addNode(addNode)

        left.output.connect(to: addNode.inputNumber1)
        right.output.connect(to: addNode.inputNumber2)
        publish(addNode.outputNumber, in: graph)

        let decodedGraph = try roundTripGraphToTemporaryFile(graph, context: harness.context)

        #expect(decodedGraph.nodes.count == 3)

        guard let decodedAddNode = decodedGraph.nodes.compactMap({ $0 as? NumberBinaryOperator }).first else {
            throw TestFailure("Expected decoded NumberBinaryOperator")
        }

        #expect(decodedAddNode.inputNumber1.connections.count == 1)
        #expect(decodedAddNode.inputNumber2.connections.count == 1)
        #expect(decodedAddNode.outputNumber.published)

        let context = harness.makeExecutionContext(time: 600, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: decodedGraph)
        try harness.render(graph: decodedGraph, executionInfo: context)
        harness.renderer.stopExecution(graph: decodedGraph)

        try expectEqual(decodedAddNode.outputNumber.value, 21)
    }

    @Test("Serialized subgraph preserves published proxies and decoded execution")
    func serializedSubgraphRoundTripsAndExecutes() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let source = PassThroughNode<Float>(context: harness.context)
        let subgraphNode = SubgraphNode(context: harness.context)
        let innerAdd = NumberBinaryOperator(context: harness.context)

        source.input.value = 5
        innerAdd.inputNumber2.value = 6
        innerAdd.inputParam.value = "Add"

        graph.addNode(source)
        graph.addNode(subgraphNode)

        subgraphNode.subGraph.addNode(innerAdd)
        innerAdd.inputNumber1.published = true
        innerAdd.outputNumber.published = true
        subgraphNode.subGraph.rebuildPublishedParameterGroup()

        let proxyInput = try floatPort(named: "Number A", kind: .Inlet, on: subgraphNode)
        let proxyOutput = try floatPort(named: "Number", kind: .Outlet, on: subgraphNode)

        source.output.connect(to: proxyInput)
        publish(proxyOutput, in: graph)

        let decodedGraph = try roundTripGraphToTemporaryFile(graph, context: harness.context)

        guard let decodedSubgraph = decodedGraph.nodes.compactMap({ $0 as? SubgraphNode }).first else {
            throw TestFailure("Expected decoded SubgraphNode")
        }

        let decodedProxyInput = try floatPort(named: "Number A", kind: .Inlet, on: decodedSubgraph)
        let decodedProxyOutput = try floatPort(named: "Number", kind: .Outlet, on: decodedSubgraph)

        #expect(decodedProxyInput.connections.count == 1)
        #expect(decodedProxyOutput.published)
        #expect(decodedSubgraph.subGraph.nodes.count == 1)

        let context = harness.makeExecutionContext(time: 700, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: decodedGraph)
        try harness.render(graph: decodedGraph, executionInfo: context)
        harness.renderer.stopExecution(graph: decodedGraph)

        try expectEqual(decodedProxyOutput.value, 11)
    }

    @Test("Serialized nested subgraph binds proxy ports against the decoded inner graph")
    func serializedNestedSubgraphRoundTripsAndExecutes() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let source = PassThroughNode<Float>(context: harness.context)
        let outerSubgraph = SubgraphNode(context: harness.context)
        let innerSubgraph = SubgraphNode(context: harness.context)
        let innerAdd = NumberBinaryOperator(context: harness.context)

        source.input.value = 5
        innerAdd.inputNumber2.value = 7
        innerAdd.inputParam.value = "Add"

        graph.addNode(source)
        graph.addNode(outerSubgraph)

        innerSubgraph.subGraph.addNode(innerAdd)
        innerAdd.inputNumber1.published = true
        innerAdd.outputNumber.published = true
        innerSubgraph.subGraph.rebuildPublishedParameterGroup()

        let innerProxyInput = try floatPort(named: "Number A", kind: .Inlet, on: innerSubgraph)
        let innerProxyOutput = try floatPort(named: "Number", kind: .Outlet, on: innerSubgraph)
        innerProxyInput.published = true
        innerProxyOutput.published = true

        outerSubgraph.subGraph.addNode(innerSubgraph)
        outerSubgraph.subGraph.rebuildPublishedParameterGroup()

        let outerProxyInput = try floatPort(named: "Number A", kind: .Inlet, on: outerSubgraph)
        let outerProxyOutput = try floatPort(named: "Number", kind: .Outlet, on: outerSubgraph)

        source.output.connect(to: outerProxyInput)
        publish(outerProxyOutput, in: graph)

        let decodedGraph = try roundTripGraphToTemporaryFile(graph, context: harness.context)

        guard let decodedOuterSubgraph = decodedGraph.nodes.compactMap({ $0 as? SubgraphNode }).first else {
            throw TestFailure("Expected decoded outer SubgraphNode")
        }

        let decodedOuterProxyInput = try floatPort(named: "Number A", kind: .Inlet, on: decodedOuterSubgraph)
        let decodedOuterProxyOutput = try floatPort(named: "Number", kind: .Outlet, on: decodedOuterSubgraph)
        let decodedInnerSubgraph = try requireValue(
            decodedOuterSubgraph.subGraph.nodes.compactMap { $0 as? SubgraphNode }.first,
            "Expected decoded inner SubgraphNode"
        )
        let decodedInnerProxyInput = try floatPort(named: "Number A", kind: .Inlet, on: decodedInnerSubgraph)
        let decodedInnerProxyOutput = try floatPort(named: "Number", kind: .Outlet, on: decodedInnerSubgraph)

        #expect(decodedOuterProxyInput.connections.count == 1)
        #expect(decodedOuterProxyOutput.published)
        #expect(decodedInnerProxyInput.published)
        #expect(decodedInnerProxyOutput.published)
        #expect(decodedOuterProxyInput.id == decodedInnerProxyInput.id)
        #expect(decodedOuterProxyOutput.id == decodedInnerProxyOutput.id)

        let context = harness.makeExecutionContext(time: 750, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: decodedGraph)
        try harness.render(graph: decodedGraph, executionInfo: context)
        harness.renderer.stopExecution(graph: decodedGraph)

        try expectEqual(decodedOuterProxyOutput.value, 12)
    }

    @Test("Serialized deferred subgraph still renders decoded outputs")
    func serializedDeferredSubgraphRoundTripsAndExecutes() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let deferred = DeferredSubgraphNode(context: harness.context)

        deferred.inputWidth.value = 48
        deferred.inputHeight.value = 24

        let geometry = BoxGeometryNode(context: harness.context)
        let material = BasicColorMaterialNode(context: harness.context)
        let mesh = MeshNode(context: harness.context)

        deferred.subGraph.addNode(geometry)
        deferred.subGraph.addNode(material)
        deferred.subGraph.addNode(mesh)

        geometry.outputGeometry.connect(to: mesh.inputGeometry)
        material.outputMaterial.connect(to: mesh.inputMaterial)

        graph.addNode(deferred)

        let decodedGraph = try roundTripGraphToTemporaryFile(graph, context: harness.context)

        guard let decodedDeferred = decodedGraph.nodes.compactMap({ $0 as? DeferredSubgraphNode }).first else {
            throw TestFailure("Expected decoded DeferredSubgraphNode")
        }

        #expect(decodedDeferred.inputWidth.value == 48)
        #expect(decodedDeferred.inputHeight.value == 24)
        #expect(decodedDeferred.subGraph.nodes.compactMap { $0 as? MeshNode }.count == 1)

        let context = harness.makeExecutionContext(time: 800, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: decodedGraph)
        try harness.render(graph: decodedGraph, executionInfo: context)
        harness.renderer.stopExecution(graph: decodedGraph)

        let colorImage = try requireValue(decodedDeferred.outputColorTexture.value, "Expected decoded deferred color output")
        #expect(colorImage.texture.width == 48)
        #expect(colorImage.texture.height == 24)

        let depthImage = try requireValue(decodedDeferred.outputDepthTexture.value, "Expected decoded deferred depth output")
        #expect(depthImage.texture.width == 48)
        #expect(depthImage.texture.height == 24)
    }

    @Test("Serialized deferred MRT subgraph restores auxiliary outputs and executes")
    func serializedDeferredMRTSubgraphRoundTripsAndExecutes() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let deferred = DeferredSubgraphNode(context: harness.context)
        deferred.inputWidth.value = 56
        deferred.inputHeight.value = 28
        deferred.deferredMRTEnabled = true

        let geometry = BoxGeometryNode(context: harness.context)
        let material = StandardMaterialNode(context: harness.context)
        let mesh = MeshNode(context: harness.context)

        deferred.subGraph.addNode(geometry)
        deferred.subGraph.addNode(material)
        deferred.subGraph.addNode(mesh)

        geometry.outputGeometry.connect(to: mesh.inputGeometry)
        material.outputMaterial.connect(to: mesh.inputMaterial)

        graph.addNode(deferred)

        let decodedGraph = try roundTripGraphToTemporaryFile(graph, context: harness.context)

        guard let decodedDeferred = decodedGraph.nodes.compactMap({ $0 as? DeferredSubgraphNode }).first else {
            throw TestFailure("Expected decoded DeferredSubgraphNode")
        }

        #expect(decodedDeferred.deferredMRTEnabled)
        _ = try imagePort(named: "Albedo Texture", kind: .Outlet, on: decodedDeferred)
        _ = try imagePort(named: "Normals Texture", kind: .Outlet, on: decodedDeferred)
        _ = try imagePort(named: "PBR Texture", kind: .Outlet, on: decodedDeferred)
        _ = try imagePort(named: "Velocity Texture", kind: .Outlet, on: decodedDeferred)
        _ = try imagePort(named: "Emissive Texture", kind: .Outlet, on: decodedDeferred)

        let context = harness.makeExecutionContext(time: 850, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: decodedGraph)
        try harness.render(graph: decodedGraph, executionInfo: context)
        harness.renderer.stopExecution(graph: decodedGraph)

        let albedoImage = try requireValue(imagePort(named: "Albedo Texture", kind: .Outlet, on: decodedDeferred).value, "Expected decoded deferred albedo output")
        let velocityImage = try requireValue(imagePort(named: "Velocity Texture", kind: .Outlet, on: decodedDeferred).value, "Expected decoded deferred velocity output")

        #expect(albedoImage.texture.width == 56)
        #expect(albedoImage.texture.height == 28)
        #expect(velocityImage.texture.width == 56)
        #expect(velocityImage.texture.height == 28)
    }
}
