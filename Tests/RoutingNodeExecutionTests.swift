import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

private struct RoutingExecutionTestHarness
{
    let context: Context
    let renderer: GraphRenderer

    init?()
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        self.context = Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
        self.renderer = GraphRenderer(context: context)
        self.renderer.resize(size: (width: 64, height: 64), scaleFactor: 1.0)
    }

    func makeExecutionInfo(frameNumber: Int) -> GraphExecutionInfo
    {
        GraphExecutionInfo(
            timing: GraphExecutionTiming(
                time: TimeInterval(frameNumber),
                deltaTime: 0,
                displayTime: TimeInterval(frameNumber),
                systemTime: TimeInterval(frameNumber),
                frameNumber: frameNumber
            )
        )
    }

    func execute(_ graph: Graph, frameNumber: Int = 0) throws
    {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.colorPixelFormat,
            width: 64,
            height: 64,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]

        guard let texture = context.device.makeTexture(descriptor: descriptor),
              let commandBuffer = renderer.commandQueue.makeCommandBuffer()
        else {
            throw RoutingTestFailure("Unable to create render resources")
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        renderer.execute(graph: graph,
                         executionInfo: makeExecutionInfo(frameNumber: frameNumber),
                         renderPassDescriptor: renderPassDescriptor,
                         commandBuffer: commandBuffer)

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error
        {
            throw error
        }
    }
}

private struct RoutingTestFailure: Error, CustomStringConvertible
{
    let description: String

    init(_ description: String)
    {
        self.description = description
    }
}

private final class CountingFloatProviderNode: Node
{
    override class var name: String { "Counting Float Provider" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Test provider that counts executions." }

    var value: Float
    var executionCount = 0

    var output: NodePort<Float> { port(named: "output") }

    init(context: Context, value: Float)
    {
        self.value = value
        super.init(context: context)
    }

    required init(context: Context)
    {
        self.value = 0
        super.init(context: context)
    }

    required init(from decoder: any Decoder) throws
    {
        self.value = 0
        try super.init(from: decoder)
    }

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [
            ("output", NodePort<Float>(name: "Output", kind: .Outlet)),
        ]
    }

    override func execute(renderer: GraphRenderer,
                          executionInfo: GraphExecutionInfo,
                          renderPassDescriptor: MTLRenderPassDescriptor,
                          commandBuffer: MTLCommandBuffer)
    {
        executionCount += 1
        output.send(value, force: true)
    }
}

private final class CountingIntProviderNode: Node
{
    override class var name: String { "Counting Int Provider" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Test index provider that counts executions." }

    var value: Int
    var executionCount = 0

    var output: NodePort<Int> { port(named: "output") }

    init(context: Context, value: Int)
    {
        self.value = value
        super.init(context: context)
    }

    required init(context: Context)
    {
        self.value = 0
        super.init(context: context)
    }

    required init(from decoder: any Decoder) throws
    {
        self.value = 0
        try super.init(from: decoder)
    }

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [
            ("output", NodePort<Int>(name: "Output", kind: .Outlet)),
        ]
    }

    override func execute(renderer: GraphRenderer,
                          executionInfo: GraphExecutionInfo,
                          renderPassDescriptor: MTLRenderPassDescriptor,
                          commandBuffer: MTLCommandBuffer)
    {
        executionCount += 1
        output.send(value, force: true)
    }
}

private final class CountingFloatConsumerNode: Node
{
    override class var name: String { "Counting Float Consumer" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Test consumer that counts executions." }

    var executionCount = 0
    var lastValue: Float?

    var input: NodePort<Float> { port(named: "input") }

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [
            ("input", NodePort<Float>(name: "Input", kind: .Inlet)),
        ]
    }

    override func execute(renderer: GraphRenderer,
                          executionInfo: GraphExecutionInfo,
                          renderPassDescriptor: MTLRenderPassDescriptor,
                          commandBuffer: MTLCommandBuffer)
    {
        executionCount += 1
        lastValue = input.value
    }
}

private func publish(_ port: Fabric.Port, in graph: Graph)
{
    port.published = true
    graph.rebuildPublishedParameterGroup()
}

@Suite("Routing Nodes")
struct RoutingNodeExecutionTests
{
    @Test("Switch only evaluates selected input branch")
    func switchOnlyEvaluatesSelectedInputBranch() throws
    {
        guard let harness = RoutingExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let index = CountingIntProviderNode(context: harness.context, value: 1)
        let inactive = CountingFloatProviderNode(context: harness.context, value: 10)
        let active = CountingFloatProviderNode(context: harness.context, value: 20)
        let switchNode = SwitchNode(context: harness.context, routeCount: 2, portType: .Float)

        graph.addNode(index)
        graph.addNode(inactive)
        graph.addNode(active)
        graph.addNode(switchNode)

        index.output.connect(to: switchNode.inputIndex)
        inactive.output.connect(to: switchNode.port(named: "input0", as: NodePort<Float>.self))
        active.output.connect(to: switchNode.port(named: "input1", as: NodePort<Float>.self))
        publish(switchNode.output, in: graph)

        try harness.execute(graph)

        #expect(index.executionCount == 1)
        #expect(inactive.executionCount == 0)
        #expect(active.executionCount == 1)
        #expect((switchNode.output as? NodePort<Float>)?.value == 20)
    }

    @Test("Switch virtual strategy forwards boxed values")
    func switchVirtualStrategyForwardsBoxedValues() throws
    {
        guard let harness = RoutingExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let source = CountingFloatProviderNode(context: harness.context, value: 12)
        let switchNode = SwitchNode(context: harness.context, routeCount: 2, portType: .Virtual)

        switchNode.inputIndex.value = 0

        graph.addNode(source)
        graph.addNode(switchNode)

        source.output.connect(to: switchNode.port(named: "input0", as: NodePort<PortValue>.self))
        publish(switchNode.output, in: graph)

        try harness.execute(graph)

        #expect((switchNode.output as? NodePort<PortValue>)?.value == .Float(12))
    }

    @Test("Gate only evaluates selected output branch")
    func gateOnlyEvaluatesSelectedOutputBranch() throws
    {
        guard let harness = RoutingExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let index = CountingIntProviderNode(context: harness.context, value: 1)
        let source = CountingFloatProviderNode(context: harness.context, value: 30)
        let gate = GateNode(context: harness.context, routeCount: 2, portType: .Float)
        let inactiveConsumer = CountingFloatConsumerNode(context: harness.context)
        let activeConsumer = CountingFloatConsumerNode(context: harness.context)

        graph.addNode(index)
        graph.addNode(source)
        graph.addNode(gate)
        graph.addNode(inactiveConsumer)
        graph.addNode(activeConsumer)

        index.output.connect(to: gate.inputIndex)
        source.output.connect(to: gate.port(named: "input", as: NodePort<Float>.self))
        gate.port(named: "output0", as: NodePort<Float>.self).connect(to: inactiveConsumer.input)
        gate.port(named: "output1", as: NodePort<Float>.self).connect(to: activeConsumer.input)

        try harness.execute(graph)

        #expect(index.executionCount == 1)
        #expect(source.executionCount == 1)
        #expect(inactiveConsumer.executionCount == 0)
        #expect(activeConsumer.executionCount == 1)
        #expect(activeConsumer.lastValue == 30)
    }

    @Test("Routing nodes are registered")
    func routingNodesAreRegistered()
    {
        let availableNames = Set(NodeRegistry.shared.availableNodes.map(\.nodeName))
        #expect(availableNames.contains(SwitchNode.name))
        #expect(availableNames.contains(GateNode.name))
    }
}
