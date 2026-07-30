import Testing
import Foundation
import Metal
import os
@testable import Fabric
import Satin

/// Exercises the synchronization contract on Graph.structuralMutationLock:
/// main-thread structural mutations (Settings-driven port rebuilds,
/// connect/disconnect) serialize against an off-main execute loop. Run under
/// Thread Sanitizer these tests fail without the lock; without TSan they still
/// exercise the racing interleavings (registry churn during an execute pass)
/// far more often than real usage does.
/// Consumer that anchors the execution plan so the churned nodes upstream of it
/// are actually scheduled and read by every pass.
private final class RecordingFloatConsumerNode: Node
{
    override class var name: String { "Recording Float Consumer" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Test consumer recording the last value received." }

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
        lastValue = input.value
    }
}

@Suite("Structural Mutation Lock")
struct StructuralMutationLockTests
{
    /// Runs `mutate` on the main queue `iterations` times while a background
    /// thread executes `graph` continuously, mirroring the app's threading:
    /// user edits on main, rendering off-main.
    private func churnAgainstExecution(harness: GraphExecutionTestHarness,
                                       graph: Graph,
                                       iterations: Int,
                                       mutate: @escaping (Int) -> Void) throws
    {
        let stopExecuting = OSAllocatedUnfairLock(initialState: false)

        let executor = Thread {
            var frameNumber = 0
            while !stopExecuting.withLock({ $0 })
            {
                _ = try? harness.execute(graph, frameNumber: frameNumber, checkCommandBufferError: false)
                frameNumber += 1
            }
        }
        executor.start()

        for iteration in 0..<iterations
        {
            DispatchQueue.main.sync { mutate(iteration) }
        }

        stopExecuting.withLock { $0 = true }
        while executor.isExecuting { usleep(1000) }
    }

    @Test("Settings-driven port rebuilds serialize against a concurrent execute loop")
    func portRebuildsDuringExecution() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 32, renderHeight: 32) else { return }

        let graph = Graph(context: harness.context)
        let sampleAndHold = SampleAndHoldNode(context: harness.context, portType: .Float)
        let consumer = RecordingFloatConsumerNode(context: harness.context)
        graph.addNode(sampleAndHold)
        graph.addNode(consumer)

        // Anchor the plan: with the consumer downstream, every pass pulls and
        // executes the sample-and-hold whose ports the churn is rebuilding.
        if let output: Fabric.Port = sampleAndHold.findPort(named: "outputValue")
        {
            output.connect(to: consumer.input)
        }

        // Every strategy switch rebuilds the node's dynamic port set through
        // removePort/addDynamicPort while the executor is mid-pass, and rewires
        // the replacement ports' connections.
        let strategies: [PortType] = [.Float, .Virtual, .Vector3, .Float]
        try churnAgainstExecution(harness: harness, graph: graph, iterations: 500) { iteration in
            sampleAndHold.strategy = strategies[iteration % strategies.count].rawValue
        }

        #expect(!sampleAndHold.ports.isEmpty)
    }

    @Test("Connect/disconnect churn serializes against a concurrent execute loop")
    func connectionChurnDuringExecution() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 32, renderHeight: 32) else { return }

        let graph = Graph(context: harness.context)
        let sourceA = NumberBinaryOperator(context: harness.context)
        let sourceB = NumberBinaryOperator(context: harness.context)
        let sink = NumberBinaryOperator(context: harness.context)
        let consumer = RecordingFloatConsumerNode(context: harness.context)
        graph.addNode(sourceA)
        graph.addNode(sourceB)
        graph.addNode(sink)
        graph.addNode(consumer)

        // Anchor the plan so every pass pulls through the churned connections.
        sink.outputNumber.connect(to: consumer.input)

        // Alternate which source feeds the sink — every flip is a disconnect,
        // a connect, a Connection register/unregister, and a plan rebuild on
        // the next pass, while the executor reads topology.
        try churnAgainstExecution(harness: harness, graph: graph, iterations: 500) { iteration in
            let source = iteration % 2 == 0 ? sourceA : sourceB
            source.outputNumber.connect(to: sink.inputNumber1)
        }

        #expect(sink.inputNumber1.connections.count == 1)
    }
}
