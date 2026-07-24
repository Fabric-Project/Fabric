import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

// Common scaffolding for the counting provider test nodes below. Providers of Float, Int and
// [String: Int] payloads differ only in their payload type, so a single generic class covers all
// three (aliased below to keep call sites unchanged). `CountingProviderDefaultValue` supplies the
// zero/empty value needed by the two required initializers, which never receive a real payload.
private protocol CountingProviderDefaultValue
{
    init()
}

extension Float: CountingProviderDefaultValue {}
extension Int: CountingProviderDefaultValue {}
extension Dictionary: CountingProviderDefaultValue where Key == String, Value == Int {}

private final class CountingProviderNode<PayloadValue: PortValueRepresentable & CountingProviderDefaultValue>: Node
{
    override class var name: String { "Counting Provider" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Test provider that counts executions." }

    var value: PayloadValue
    var executionCount = 0

    var output: NodePort<PayloadValue> { port(named: "output") }

    init(context: Context, value: PayloadValue)
    {
        self.value = value
        super.init(context: context)
    }

    required init(context: Context)
    {
        self.value = PayloadValue()
        super.init(context: context)
    }

    required init(from decoder: any Decoder) throws
    {
        self.value = PayloadValue()
        try super.init(from: decoder)
    }

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [
            ("output", NodePort<PayloadValue>(name: "Output", kind: .Outlet)),
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

private typealias CountingFloatProviderNode = CountingProviderNode<Float>
private typealias CountingIntProviderNode = CountingProviderNode<Int>
private typealias CountingMapProviderNode = CountingProviderNode<[String: Int]>

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

private final class CountingTwoInputConsumerNode: Node
{
    override class var name: String { "Counting Two Input Consumer" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Test consumer with two inlets that counts executions." }

    var executionCount = 0
    var lastA: Float?
    var lastB: Float?

    var inputA: NodePort<Float> { port(named: "inputA") }
    var inputB: NodePort<Float> { port(named: "inputB") }

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [
            ("inputA", NodePort<Float>(name: "Input A", kind: .Inlet)),
            ("inputB", NodePort<Float>(name: "Input B", kind: .Inlet)),
        ]
    }

    override func execute(renderer: GraphRenderer,
                          executionInfo: GraphExecutionInfo,
                          renderPassDescriptor: MTLRenderPassDescriptor,
                          commandBuffer: MTLCommandBuffer)
    {
        executionCount += 1
        lastA = inputA.value
        lastB = inputB.value
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
    // A routing node picks its active branch in respondToPull(requestedOutputPort:)
    // from its index/map input. The renderer resolves controlInputPorts — pulling and
    // executing their upstream chains — before asking, so routing is correct from the
    // very first frame; the historical one-frame cold-start latency (control values
    // pulled lazily within the same pass, so the first pass read an empty port) is
    // gone, and the cold-start tests below assert first-frame routing directly.

    @Test("Switch routes correctly on the first frame")
    func switchColdStartRoutesCorrectlyOnFirstFrame() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

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

        try harness.execute(graph, frameNumber: 0)

        // The connected index resolves before the branch is chosen, so frame 0
        // already routes index 1 -> only the active branch.
        #expect(inactive.executionCount == 0)
        #expect(active.executionCount == 1)
        #expect((switchNode.output as? NodePort<Float>)?.value == 20)
    }

    @Test("Switch only evaluates selected input branch (steady state)")
    func switchOnlyEvaluatesSelectedInputBranch() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

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

        // Warm up one frame so the connected index value lands on the port, then measure
        // steady-state routing on the next frame via per-frame execution-count deltas.
        try harness.execute(graph, frameNumber: 0)
        let indexBefore = index.executionCount
        let inactiveBefore = inactive.executionCount
        let activeBefore = active.executionCount

        try harness.execute(graph, frameNumber: 1)

        #expect(index.executionCount - indexBefore == 1)
        #expect(inactive.executionCount - inactiveBefore == 0)
        #expect(active.executionCount - activeBefore == 1)
        #expect((switchNode.output as? NodePort<Float>)?.value == 20)
    }

    @Test("Switch virtual strategy forwards boxed values")
    func switchVirtualStrategyForwardsBoxedValues() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

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

    @Test("Gate routes correctly on the first frame")
    func gateColdStartRoutesCorrectlyOnFirstFrame() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

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

        try harness.execute(graph, frameNumber: 0)

        // The connected index resolves before the branch is chosen, so frame 0
        // already routes index 1 -> only the active output branch.
        #expect(inactiveConsumer.executionCount == 0)
        #expect(activeConsumer.executionCount == 1)
        #expect(activeConsumer.lastValue == 30)
    }

    @Test("Gate only evaluates selected output branch (steady state)")
    func gateOnlyEvaluatesSelectedOutputBranch() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

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

        // Warm up one frame so the connected index value lands on the port, then measure
        // steady-state routing on the next frame via per-frame execution-count deltas.
        try harness.execute(graph, frameNumber: 0)
        let sourceBefore = source.executionCount
        let inactiveBefore = inactiveConsumer.executionCount
        let activeBefore = activeConsumer.executionCount

        try harness.execute(graph, frameNumber: 1)

        #expect(source.executionCount - sourceBefore == 1)
        #expect(inactiveConsumer.executionCount - inactiveBefore == 0)
        #expect(activeConsumer.executionCount - activeBefore == 1)
        #expect(activeConsumer.lastValue == 30)
    }

    @Test("Gate recovers routing with a connected index (no index-starvation deadlock)")
    func gateRecoversWithConnectedIndex() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let graph = Graph(context: harness.context)
        let index = CountingIntProviderNode(context: harness.context, value: 1)
        let source = CountingFloatProviderNode(context: harness.context, value: 30)
        let gate = GateNode(context: harness.context, routeCount: 2, portType: .Float)
        let consumer = CountingFloatConsumerNode(context: harness.context)

        for node in [index, source, gate, consumer] as [Node]
        {
            graph.addNode(node)
        }

        index.output.connect(to: gate.inputIndex)
        source.output.connect(to: gate.port(named: "input", as: NodePort<Float>.self))
        // Only output 1 has a consumer; whether it is selected depends entirely
        // on the connected index chain staying alive.
        gate.port(named: "output1", as: NodePort<Float>.self).connect(to: consumer.input)

        try harness.execute(graph, frameNumber: 0)
        try harness.execute(graph, frameNumber: 1)

        // The index chain resolves before route selection every frame — it can
        // never starve (the class fixed for Matrix Switch in e776d909), and with
        // control-first resolution route 1 is selected from frame 0.
        #expect(index.executionCount == 2)
        #expect(consumer.executionCount == 2)
        #expect(consumer.lastValue == 30)
    }

    @Test("A declined pull keeps the control chain alive without evaluating the data input")
    func declinedPullLeavesDataInputLazy() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let graph = Graph(context: harness.context)
        let index = CountingIntProviderNode(context: harness.context, value: 0)
        let source = CountingFloatProviderNode(context: harness.context, value: 30)
        let gate = GateNode(context: harness.context, routeCount: 2, portType: .Float)
        let consumer = CountingFloatConsumerNode(context: harness.context)

        for node in [index, source, gate, consumer] as [Node]
        {
            graph.addNode(node)
        }

        index.output.connect(to: gate.inputIndex)
        source.output.connect(to: gate.port(named: "input", as: NodePort<Float>.self))
        // The index selects route 0 every frame, so the sole consumer — on
        // output 1 — declines every pull.
        gate.port(named: "output1", as: NodePort<Float>.self).connect(to: consumer.input)

        try harness.execute(graph, frameNumber: 0)
        try harness.execute(graph, frameNumber: 1)

        // A declined pull resolves only the gate's control inputs (its Index
        // chain); the data input feeds no consumed route, so its provider must
        // stay lazy rather than being evaluated for a value nobody reads.
        #expect(index.executionCount == 2)
        #expect(source.executionCount == 0)
        #expect(consumer.executionCount == 0)
    }

    @Test("A gated inlet does not stall a consumer's live inlets")
    func gatedInletDoesNotStallSiblingInlets() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let graph = Graph(context: harness.context)
        let source = CountingFloatProviderNode(context: harness.context, value: 30)
        let live = CountingFloatProviderNode(context: harness.context, value: 42)
        let gate = GateNode(context: harness.context, routeCount: 2, portType: .Float)
        let consumer = CountingTwoInputConsumerNode(context: harness.context)

        // Output 0 is unselected, so inlet A hangs off a frozen branch.
        gate.inputIndex.value = 1

        for node in [source, live, gate, consumer] as [Node]
        {
            graph.addNode(node)
        }

        source.output.connect(to: gate.port(named: "input", as: NodePort<Float>.self))
        gate.port(named: "output0", as: NodePort<Float>.self).connect(to: consumer.inputA)
        live.output.connect(to: consumer.inputB)

        try harness.execute(graph, frameNumber: 0)
        try harness.execute(graph, frameNumber: 1)

        // The unselected gate branch freezes inlet A only; the live inlet keeps
        // updating and the consumer keeps running every frame.
        #expect(consumer.executionCount == 2)
        #expect(consumer.lastA == nil)
        #expect(consumer.lastB == 42)
        #expect(live.executionCount == 2)
    }

    @Test("Consumers of a fully gated branch freeze regardless of pull order")
    func fullyGatedBranchFreezesAllConsumers() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let graph = Graph(context: harness.context)
        let source = CountingFloatProviderNode(context: harness.context, value: 30)
        let gate = GateNode(context: harness.context, routeCount: 2, portType: .Float)
        let passthrough = SwitchNode(context: harness.context, routeCount: 2, portType: .Float)
        let firstConsumer = CountingFloatConsumerNode(context: harness.context)
        let secondConsumer = CountingFloatConsumerNode(context: harness.context)

        gate.inputIndex.value = 1        // output 0 is unselected
        passthrough.inputIndex.value = 0 // routes input 0, fed by the unselected branch

        for node in [source, gate, passthrough, firstConsumer, secondConsumer] as [Node]
        {
            graph.addNode(node)
        }

        source.output.connect(to: gate.port(named: "input", as: NodePort<Float>.self))
        gate.port(named: "output0", as: NodePort<Float>.self).connect(to: passthrough.port(named: "input0", as: NodePort<Float>.self))
        passthrough.output.connect(to: firstConsumer.input)
        passthrough.output.connect(to: secondConsumer.input)

        try harness.execute(graph, frameNumber: 0)
        try harness.execute(graph, frameNumber: 1)

        // Before declined-pull tracking, the first consumer's abandoned pull left
        // the intermediate switch stranded in .processing, so whichever consumer
        // pulled second executed against the never-run switch — behavior depended
        // purely on pull order. Both must freeze.
        #expect(firstConsumer.executionCount == 0)
        #expect(secondConsumer.executionCount == 0)
    }

    @Test("Matrix Switch cross-routes each input to its mapped output")
    func matrixSwitchCrossRoutesInputsToOutputs() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

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
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

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
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

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
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

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

        // The map chain resolves before routing is read, so the connected map
        // routes correctly from the first frame. The node must never gate itself
        // off, or the map could never influence later frames.
        try harness.execute(graph, frameNumber: 0)
        try harness.execute(graph, frameNumber: 1)

        #expect(consumer0.lastValue == 20)
        #expect(consumer1.lastValue == 10)
    }

    @Test("Feedback injection follows a Switch route change without a topology change")
    func feedbackInjectionFollowsRouteChange() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let graph = Graph(context: harness.context)
        let plain = CountingFloatProviderNode(context: harness.context, value: 5)
        let loopback = CountingFloatProviderNode(context: harness.context, value: 9)
        let switchNode = SwitchNode(context: harness.context, routeCount: 2, portType: .Float)

        graph.addNode(plain)
        graph.addNode(loopback)
        graph.addNode(switchNode)

        plain.output.connect(to: switchNode.port(named: "input0", as: NodePort<Float>.self))
        loopback.output.connect(to: switchNode.port(named: "input1", as: NodePort<Float>.self))

        // Drive the feedback cache the way pullNode does across three frames:
        // frame 0 caches the loopback's outputs, frame 1 visits the switch while
        // it selects input 0 (populating any candidate cache for that selection),
        // frame 2 switches to input 1 while the loopback is mid-traversal — a
        // feedback back-edge, so the previous frame's value must be injected
        // into the *newly* selected inlet.
        let cache = GraphRendererFeedbackCache(graphID: graph.id)

        loopback.output.send(9, force: true)
        cache.cacheProcessedNode(loopback, executionInfo: harness.makeExecutionInfo(frameNumber: 0))

        // The renderer injects feedback for each pull's active inlets, taken
        // from the node's PullResponse at that moment; do the same here.
        func pulledInlets() throws -> [Fabric.Port]
        {
            guard case .evaluate(let pulling) = switchNode.respondToPull(requestedOutputPort: switchNode.output)
            else { throw GraphExecutionTestFailure("Switch declined its own output pull") }
            return pulling
        }

        let frame1 = harness.makeExecutionInfo(frameNumber: 1)
        cache.resetCacheFor(executionInfo: frame1)
        switchNode.inputIndex.value = 0
        cache.setProcessingState(.processing, forNode: switchNode, executionInfo: frame1)
        cache.injectFeedback(forInlets: try pulledInlets(), executionInfo: frame1)
        loopback.output.send(9, force: true)
        cache.cacheProcessedNode(loopback, executionInfo: frame1)

        let frame2 = harness.makeExecutionInfo(frameNumber: 2)
        cache.resetCacheFor(executionInfo: frame2)
        switchNode.inputIndex.value = 1
        let selectedInlet = switchNode.port(named: "input1", as: NodePort<Float>.self)
        selectedInlet.value = 123
        cache.setProcessingState(.processing, forNode: loopback, executionInfo: frame2)
        cache.setProcessingState(.processing, forNode: switchNode, executionInfo: frame2)
        cache.injectFeedback(forInlets: try pulledInlets(), executionInfo: frame2)

        // With candidates cached from the input-0 selection, the injection missed
        // the newly selected inlet and it kept its sentinel value.
        #expect(selectedInlet.value == 9)
    }

    @Test("Round-tripping a Switch with more than two routes preserves ports and connections")
    func routeCountRoundTripPreservesPortsAndConnections() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let graph = Graph(context: harness.context)
        let upstream = SwitchNode(context: harness.context, routeCount: 2, portType: .Float)
        let switchNode = SwitchNode(context: harness.context, routeCount: 4, portType: .Float)

        graph.addNode(upstream)
        graph.addNode(switchNode)

        upstream.output.connect(to: switchNode.port(named: "input3", as: NodePort<Float>.self))
        let savedInput3ID = switchNode.port(named: "input3", as: NodePort<Float>.self).id

        let data = try JSONEncoder().encode(graph)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context)
        let decodedGraph = try decoder.decode(Graph.self, from: data)

        let decodedSwitch = try #require(decodedGraph.nodes.first(where: { $0.id == switchNode.id }) as? SwitchNode)
        #expect(decodedSwitch.routeCount == 4)

        // The decode must rebuild ports with the saved route count in place —
        // otherwise the high-index ports are torn down and recreated with fresh
        // UUIDs, and the graph's UUID-keyed connection restore silently drops
        // everything wired to routes >= 2.
        let decodedInput3 = try #require(decodedSwitch.findPort(named: "input3", as: NodePort<Float>.self))
        #expect(decodedInput3.id == savedInput3ID)
        #expect(decodedInput3.connections.count == 1)
    }

    @Test("Reducing route count removes the stale high-index ports")
    func reducingRouteCountRemovesStalePorts() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let switchNode = SwitchNode(context: harness.context, routeCount: 4, portType: .Float)
        switchNode.setRouteCount(2)

        #expect(switchNode.findPort(named: "input0", as: NodePort<Float>.self) != nil)
        #expect(switchNode.findPort(named: "input1", as: NodePort<Float>.self) != nil)
        #expect(switchNode.findPort(named: "input2", as: NodePort<Float>.self) == nil)
        #expect(switchNode.findPort(named: "input3", as: NodePort<Float>.self) == nil)

        let matrix = MatrixSwitchNode(context: harness.context, routeCount: 3, portType: .Float)
        matrix.setRouteCount(2)

        #expect(matrix.findPort(named: "input2", as: NodePort<Float>.self) == nil)
        #expect(matrix.findPort(named: "output2", as: NodePort<Float>.self) == nil)
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
