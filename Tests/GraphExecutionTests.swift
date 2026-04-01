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
    ) -> GraphExecutionContext {
        GraphExecutionContext(
            graphRenderer: self.renderer,
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

    func render(graph: Graph, executionContext: GraphExecutionContext, drawScene: Bool = true) throws {
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
                executionContext: executionContext,
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer
            )
        } else {
            self.renderer.execute(
                graph: graph,
                executionContext: executionContext,
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

@Suite("Graph Execution")
struct GraphExecutionTests {

    @Test("Number node outputs configured value after one render")
    func numberNodeOutputsConfiguredValue() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let numberNode = NumberNode(context: harness.context)
        numberNode.inputNumber.value = 3.5
        graph.addNode(numberNode)
        publish(numberNode.outputNumber, in: graph)

        let context = harness.makeExecutionContext(time: 10, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: graph, executionContext: context)
        try harness.render(graph: graph, executionContext: context)
        harness.renderer.stopExecution(graph: graph, executionContext: context)

        try expectEqual(numberNode.outputNumber.value, 3.5)
    }

    @Test("Connected number nodes feed Number Binary Operator add")
    func connectedNumberNodesComputeSum() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let left = NumberNode(context: harness.context)
        let right = NumberNode(context: harness.context)
        let addNode = NumberBinaryOperator(context: harness.context)

        left.inputNumber.value = 2.25
        right.inputNumber.value = 4.75
        addNode.inputParam.value = "Add"

        graph.addNode(left)
        graph.addNode(right)
        graph.addNode(addNode)

        left.outputNumber.connect(to: addNode.inputNumber1)
        right.outputNumber.connect(to: addNode.inputNumber2)
        publish(addNode.outputNumber, in: graph)

        let context = harness.makeExecutionContext(time: 20, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: graph, executionContext: context)
        try harness.render(graph: graph, executionContext: context)
        harness.renderer.stopExecution(graph: graph, executionContext: context)

        try expectEqual(addNode.outputNumber.value, 7.0)
    }

    @Test("Updating an upstream number recomputes the downstream output")
    func downstreamOutputUpdatesAfterInputChange() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let left = NumberNode(context: harness.context)
        let right = NumberNode(context: harness.context)
        let addNode = NumberBinaryOperator(context: harness.context)

        left.inputNumber.value = 1
        right.inputNumber.value = 2
        addNode.inputParam.value = "Add"

        graph.addNode(left)
        graph.addNode(right)
        graph.addNode(addNode)

        left.outputNumber.connect(to: addNode.inputNumber1)
        right.outputNumber.connect(to: addNode.inputNumber2)
        publish(addNode.outputNumber, in: graph)

        let firstContext = harness.makeExecutionContext(time: 30, deltaTime: 0, frameNumber: 0)
        let secondContext = harness.makeExecutionContext(time: 31, deltaTime: 1, frameNumber: 1)

        harness.renderer.startExecution(graph: graph, executionContext: firstContext)
        try harness.render(graph: graph, executionContext: firstContext)
        try expectEqual(addNode.outputNumber.value, 3)

        right.inputNumber.value = 9
        try harness.render(graph: graph, executionContext: secondContext)
        harness.renderer.stopExecution(graph: graph, executionContext: secondContext)

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

        harness.renderer.startExecution(graph: graph, executionContext: firstContext)
        try harness.render(graph: graph, executionContext: firstContext)
        try expectEqual(timeNode.outputNumber.value, 0)

        try harness.render(graph: graph, executionContext: secondContext)
        harness.renderer.stopExecution(graph: graph, executionContext: secondContext)

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

        harness.renderer.startExecution(graph: graph, executionContext: firstContext)
        try harness.render(graph: graph, executionContext: firstContext)
        try expectEqual(timeNode.outputNumber.value, 0)

        try harness.render(graph: graph, executionContext: secondContext)
        harness.renderer.stopExecution(graph: graph, executionContext: secondContext)

        try expectEqual(timeNode.outputNumber.value, 2.5)
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

        harness.renderer.startExecution(graph: graph, executionContext: firstContext)
        try harness.render(graph: graph, executionContext: firstContext)

        try expectEqual(renderInfoNode.outputWidth.value, 640)
        try expectEqual(renderInfoNode.outputHeight.value, 360)
        #expect(renderInfoNode.outputFrameNumber.value == 0)

        try harness.render(graph: graph, executionContext: secondContext)
        harness.renderer.stopExecution(graph: graph, executionContext: secondContext)

        #expect(renderInfoNode.outputFrameNumber.value == 1)
    }

    @Test("Subgraph proxy inlet and outlet forward values across graphs")
    func subgraphProxyPortsForwardValues() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let source = NumberNode(context: harness.context)
        let subgraphNode = SubgraphNode(context: harness.context)
        let innerAdd = NumberBinaryOperator(context: harness.context)

        source.inputNumber.value = 4
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

        source.outputNumber.connect(to: proxyInput)
        publish(proxyOutput, in: graph)

        let context = harness.makeExecutionContext(time: 300, deltaTime: 0, frameNumber: 0)

        harness.renderer.startExecution(graph: graph, executionContext: context)
        try harness.render(graph: graph, executionContext: context)
        harness.renderer.stopExecution(graph: graph, executionContext: context)

        try expectEqual(innerAdd.inputNumber1.value, 4)
        try expectEqual(proxyOutput.value, 7)
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

        harness.renderer.startExecution(graph: graph, executionContext: context)
        try harness.render(graph: graph, executionContext: context)
        harness.renderer.stopExecution(graph: graph, executionContext: context)

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

        harness.renderer.startExecution(graph: graph, executionContext: context)
        try harness.render(graph: graph, executionContext: context)
        harness.renderer.stopExecution(graph: graph, executionContext: context)

        let colorImage = try requireValue(deferred.outputColorTexture.value, "Expected deferred color output")
        #expect(colorImage.texture.width == 64)
        #expect(colorImage.texture.height == 32)

        let depthImage = try requireValue(deferred.outputDepthTexture.value, "Expected deferred depth output")
        #expect(depthImage.texture.width == 64)
        #expect(depthImage.texture.height == 32)
    }
}
