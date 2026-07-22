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

private final class CountingMapProviderNode: Node
{
    override class var name: String { "Counting Map Provider" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Test index-map provider that counts executions." }

    var value: [String: Int]
    var executionCount = 0

    var output: NodePort<[String: Int]> { port(named: "output") }

    init(context: Context, value: [String: Int])
    {
        self.value = value
        super.init(context: context)
    }

    required init(context: Context)
    {
        self.value = [:]
        super.init(context: context)
    }

    required init(from decoder: any Decoder) throws
    {
        self.value = [:]
        try super.init(from: decoder)
    }

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [
            ("output", NodePort<[String: Int]>(name: "Output", kind: .Outlet)),
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

    @Test("Matrix Switch cross-routes each input to its mapped output")
    func matrixSwitchCrossRoutesInputsToOutputs() throws
    {
        guard let harness = RoutingExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let input0 = CountingFloatProviderNode(context: harness.context, value: 10)
        let input1 = CountingFloatProviderNode(context: harness.context, value: 20)
        let input2 = CountingFloatProviderNode(context: harness.context, value: 30)
        let matrix = MatrixSwitchNode(context: harness.context, routeCount: 3, portType: .Float)
        let consumer0 = CountingFloatConsumerNode(context: harness.context)
        let consumer1 = CountingFloatConsumerNode(context: harness.context)
        let consumer2 = CountingFloatConsumerNode(context: harness.context)

        // input 0 -> output 2, input 1 -> output 0, input 2 -> output 1
        matrix.inputMap.value = ["0": 2, "1": 0, "2": 1]

        for node in [input0, input1, input2, matrix, consumer0, consumer1, consumer2] as [Node]
        {
            graph.addNode(node)
        }

        input0.output.connect(to: matrix.port(named: "input0", as: NodePort<Float>.self))
        input1.output.connect(to: matrix.port(named: "input1", as: NodePort<Float>.self))
        input2.output.connect(to: matrix.port(named: "input2", as: NodePort<Float>.self))
        matrix.port(named: "output0", as: NodePort<Float>.self).connect(to: consumer0.input)
        matrix.port(named: "output1", as: NodePort<Float>.self).connect(to: consumer1.input)
        matrix.port(named: "output2", as: NodePort<Float>.self).connect(to: consumer2.input)

        try harness.execute(graph)

        #expect(consumer0.lastValue == 20)
        #expect(consumer1.lastValue == 30)
        #expect(consumer2.lastValue == 10)
        #expect(input0.executionCount == 1)
        #expect(input1.executionCount == 1)
        #expect(input2.executionCount == 1)
    }

    @Test("Matrix Switch does not evaluate unrouted inputs and emits nothing for unrouted outputs")
    func matrixSwitchLeavesUnroutedBranchesUnevaluated() throws
    {
        guard let harness = RoutingExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let routed = CountingFloatProviderNode(context: harness.context, value: 10)
        let unrouted = CountingFloatProviderNode(context: harness.context, value: 99)
        let matrix = MatrixSwitchNode(context: harness.context, routeCount: 2, portType: .Float)
        let activeConsumer = CountingFloatConsumerNode(context: harness.context)
        let frozenConsumer = CountingFloatConsumerNode(context: harness.context)

        // Only input 0 is mapped (-> output 0). Input 1 is absent = off; output 1 has no source.
        matrix.inputMap.value = ["0": 0]

        for node in [routed, unrouted, matrix, activeConsumer, frozenConsumer] as [Node]
        {
            graph.addNode(node)
        }

        routed.output.connect(to: matrix.port(named: "input0", as: NodePort<Float>.self))
        unrouted.output.connect(to: matrix.port(named: "input1", as: NodePort<Float>.self))
        matrix.port(named: "output0", as: NodePort<Float>.self).connect(to: activeConsumer.input)
        matrix.port(named: "output1", as: NodePort<Float>.self).connect(to: frozenConsumer.input)

        try harness.execute(graph)

        #expect(activeConsumer.lastValue == 10)
        // Output 1 has no source, so the node emits nothing for it — its consumer
        // reads the port's frozen value (nil, as it was never routed).
        #expect(frozenConsumer.lastValue == nil)
        #expect(routed.executionCount == 1)
        // Input 1 is off (absent from the map), so it is never evaluated.
        #expect(unrouted.executionCount == 0)
    }

    @Test("Matrix Switch resolves output collisions by lowest input index")
    func matrixSwitchResolvesCollisionByLowestInputIndex() throws
    {
        guard let harness = RoutingExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let winner = CountingFloatProviderNode(context: harness.context, value: 10)
        let loser = CountingFloatProviderNode(context: harness.context, value: 20)
        let matrix = MatrixSwitchNode(context: harness.context, routeCount: 2, portType: .Float)
        let consumer = CountingFloatConsumerNode(context: harness.context)

        // Both inputs target output 0 — the lower input index wins.
        matrix.inputMap.value = ["0": 0, "1": 0]

        for node in [winner, loser, matrix, consumer] as [Node]
        {
            graph.addNode(node)
        }

        winner.output.connect(to: matrix.port(named: "input0", as: NodePort<Float>.self))
        loser.output.connect(to: matrix.port(named: "input1", as: NodePort<Float>.self))
        matrix.port(named: "output0", as: NodePort<Float>.self).connect(to: consumer.input)

        try harness.execute(graph)

        #expect(consumer.lastValue == 10)
        #expect(winner.executionCount == 1)
        // The collision loser feeds no output, so it is never evaluated.
        #expect(loser.executionCount == 0)
    }

    @Test("Matrix Switch recovers routing with a connected map (no map-starvation deadlock)")
    func matrixSwitchRecoversWithConnectedMap() throws
    {
        guard let harness = RoutingExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let mapProvider = CountingMapProviderNode(context: harness.context, value: ["0": 1, "1": 0])
        let input0 = CountingFloatProviderNode(context: harness.context, value: 10)
        let input1 = CountingFloatProviderNode(context: harness.context, value: 20)
        let matrix = MatrixSwitchNode(context: harness.context, routeCount: 2, portType: .Float)
        let consumer0 = CountingFloatConsumerNode(context: harness.context)
        let consumer1 = CountingFloatConsumerNode(context: harness.context)

        for node in [mapProvider, input0, input1, matrix, consumer0, consumer1] as [Node]
        {
            graph.addNode(node)
        }

        // Map arrives via a *connection*, not a directly set value: input 0 -> output 1, input 1 -> output 0.
        mapProvider.output.connect(to: matrix.inputMap)
        input0.output.connect(to: matrix.port(named: "input0", as: NodePort<Float>.self))
        input1.output.connect(to: matrix.port(named: "input1", as: NodePort<Float>.self))
        matrix.port(named: "output0", as: NodePort<Float>.self).connect(to: consumer0.input)
        matrix.port(named: "output1", as: NodePort<Float>.self).connect(to: consumer1.input)

        // The map is empty during the first pass (its provider has not run yet), so routing
        // lags by one frame — the same cold-start latency as Switch/Gate. The node must not
        // gate itself off, or the map would never populate and routing would never recover.
        try harness.execute(graph, frameNumber: 0)
        try harness.execute(graph, frameNumber: 1)

        #expect(consumer0.lastValue == 20)
        #expect(consumer1.lastValue == 10)
    }

    @Test("Routing nodes are registered")
    func routingNodesAreRegistered()
    {
        let availableNames = Set(NodeRegistry.shared.availableNodes.map(\.nodeName))
        #expect(availableNames.contains(SwitchNode.name))
        #expect(availableNames.contains(GateNode.name))
        #expect(availableNames.contains(MatrixSwitchNode.name))
    }
}
