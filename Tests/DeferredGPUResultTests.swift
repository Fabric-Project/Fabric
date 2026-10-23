import Testing
import Metal
import Foundation
import Satin
@testable import Fabric

@Suite("Deferred GPU result delivery", .serialized)
struct DeferredGPUResultTests {
    @Test("Deferred sends stage without changing live ports; publication is explicit")
    func stagingAndPublication() throws {
        let output = NodePort<Float>(name: "Output", kind: .Outlet)
        output.value = 7
        let binding = GraphDeferredNodeBinding(outputs: [output])
        let scope = GraphDeferredResultScope()
        let state = scope.state(for: binding)
        try binding.capture(in: state) { output.send(42) }
        #expect(output.value == 7)
        state.publish(binding: binding)
        #expect(output.value == 42)
    }

    @Test("Contexts restore their own previous values, including absent values")
    func iterationIsolation() throws {
        let output = NodePort<Float>(name: "Output", kind: .Outlet)
        let binding = GraphDeferredNodeBinding(outputs: [output])
        let first = GraphDeferredResultScope().state(for: binding)
        let second = GraphDeferredResultScope().state(for: binding)
        try binding.capture(in: first) { output.send(11) }
        first.publish(binding: binding)
        #expect(output.value == 11)
        second.publish(binding: binding)
        #expect(output.value == nil)
        try binding.capture(in: second) { output.send(22) }
        second.publish(binding: binding)
        #expect(output.value == 22)
        first.publish(binding: binding)
        #expect(output.value == 11)
    }

    @Test("A first failed completion preserves an ordinary output value")
    func firstCompletionFailure() throws {
        enum Failure: Error { case decode }
        let output = NodePort<Float>(name: "Output", kind: .Outlet)
        output.send(7)
        let binding = GraphDeferredNodeBinding(outputs: [output])
        let state = GraphDeferredResultScope().state(for: binding)
        #expect(throws: Failure.self) {
            try binding.capture(in: state) {
                output.send(99)
                throw Failure.decode
            }
        }
        state.publish(binding: binding)
        #expect(output.value == 7)
    }

    @Test("A throwing completion publishes none of its partial sends")
    func atomicCompletionFailure() throws {
        enum Failure: Error { case decode }
        let output = NodePort<Float>(name: "Output", kind: .Outlet)
        let binding = GraphDeferredNodeBinding(outputs: [output])
        let state = GraphDeferredResultScope().state(for: binding)
        try binding.capture(in: state) { output.send(3) }
        #expect(throws: Failure.self) {
            try binding.capture(in: state) {
                output.send(99)
                throw Failure.decode
            }
        }
        state.publish(binding: binding)
        #expect(output.value == 3)
    }
}

private class DeferredProbeNode: Node {
    override class var name: String { "Deferred Probe" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Deferred output test" }
    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)] {
        [("output", NodePort<Int>(name: "Output", kind: .Outlet))]
    }
    var output: NodePort<Int> { port(named: "output") }
    var observed: [Int?] = []
    var requestCount = 0
    var continueAfterRequest = false
    var addTailRequest = false
    var failDecode = false
    override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo,
                          renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        observed.append(output.value)
        guard executionInfo.timing.frameNumber == 0 else { return }
        let readback = try #require(renderer.context.device.makeBuffer(length: 4, options: .storageModeShared))
        let blit = try #require(commandBuffer.makeBlitCommandEncoder())
        blit.fill(buffer: readback, range: 0..<4, value: UInt8(10 + requestCount))
        blit.endEncoding()
        let output = self.output
        let failDecode = self.failDecode
        try commandBuffer.addCompletion { [readback, output] in
            output.send(Int(readback.contents().load(as: UInt8.self)))
            if failDecode { throw GraphExecutionTestFailure("Intentional decode failure") }
        }
        requestCount += 1
        if continueAfterRequest { try renderer.waitForGPUResults(commandBuffer: commandBuffer) }
        if addTailRequest { try commandBuffer.addCompletion { output.send(99) } }
    }
}

extension DeferredGPUResultTests {
    private func execute(_ renderer: GraphRenderer, graph: Graph, harness: GraphExecutionTestHarness, frame: Int) throws {
        let commands = try #require(renderer.makeCommandBuffer())
        try renderer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: frame),
                             renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
        commands.commit()
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)
    }

    @Test("Default scope delivers only at the next CPU execution")
    func defaultScopeDelivery() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let probe = DeferredProbeNode(context: harness.context)
        graph.addNode(probe)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        try execute(renderer, graph: graph, harness: harness, frame: 0)
        #expect(probe.output.value == nil)
        try execute(renderer, graph: graph, harness: harness, frame: 1)
        #expect(probe.observed == [nil, 10])
    }

    @Test("Iterator uses the same completion API and restores one result per iteration")
    func iteratorDelivery() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let iterator = IteratorNode(context: harness.context)
        iterator.inputIteratonCount.value = 3
        let probe = DeferredProbeNode(context: harness.context)
        iterator.subGraph.addNode(probe)
        graph.addNode(iterator)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        try execute(renderer, graph: graph, harness: harness, frame: 0)
        try execute(renderer, graph: graph, harness: harness, frame: 1)
        try execute(renderer, graph: graph, harness: harness, frame: 2)
        #expect(probe.observed == [nil, nil, nil, 10, 11, 12, 10, 11, 12])
    }

    @Test("Warmed output staging reuses its typed slot")
    func stagingReusesStorage() throws {
        let output = NodePort<Float>(name: "Output", kind: .Outlet)
        let binding = GraphDeferredNodeBinding(outputs: [output])
        let state = GraphDeferredResultScope().state(for: binding)
        for index in 0..<100 {
            try binding.capture(in: state) { output.send(Float(index)) }
            state.publish(binding: binding)
        }
        #expect(state.slotCreationCount == 1)
    }
}

extension DeferredGPUResultTests {
    @Test("Nested Iterators isolate identical inner indices under different outer iterations")
    func nestedIteratorDelivery() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let outer = IteratorNode(context: harness.context)
        let inner = IteratorNode(context: harness.context)
        let probe = DeferredProbeNode(context: harness.context)
        outer.inputIteratonCount.value = 2
        inner.inputIteratonCount.value = 2
        inner.subGraph.addNode(probe)
        outer.subGraph.addNode(inner)
        graph.addNode(outer)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        try execute(renderer, graph: graph, harness: harness, frame: 0)
        try execute(renderer, graph: graph, harness: harness, frame: 1)
        try execute(renderer, graph: graph, harness: harness, frame: 2)
        #expect(probe.observed == [nil, nil, nil, nil, 10, 11, 12, 13, 10, 11, 12, 13])
    }

    @Test("Removed iteration storage cannot reappear when the count grows again")
    func removedIterationsDoNotReturnOldResults() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let iterator = IteratorNode(context: harness.context)
        let probe = DeferredProbeNode(context: harness.context)
        iterator.inputIteratonCount.value = 3
        iterator.subGraph.addNode(probe)
        graph.addNode(iterator)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        try execute(renderer, graph: graph, harness: harness, frame: 0)
        iterator.inputIteratonCount.value = 1
        try execute(renderer, graph: graph, harness: harness, frame: 1)
        iterator.inputIteratonCount.value = 3
        try execute(renderer, graph: graph, harness: harness, frame: 2)
        #expect(probe.observed == [nil, nil, nil, 10, 10, nil, nil])
    }

    @Test("Graphs and Iterators that never register completion allocate no async storage")
    func dormantPath() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let iterator = IteratorNode(context: harness.context)
        let probe = DeferredProbeNode(context: harness.context)
        iterator.subGraph.addNode(probe)
        graph.addNode(iterator)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        try execute(renderer, graph: graph, harness: harness, frame: 7)
        #expect(renderer.deferredGPUResults == nil)
        #expect(iterator.deferredScopes == nil)
        #expect(probe.deferredResultsBinding == nil)
        #expect(probe.output.deferredSendCapture == nil)
    }

    @Test("Cancellation invalidates ready requests before they can stage values")
    func cancellation() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let probe = DeferredProbeNode(context: harness.context)
        graph.addNode(probe)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        try execute(renderer, graph: graph, harness: harness, frame: 0)
        probe.cancelPendingCompletions()
        try execute(renderer, graph: graph, harness: harness, frame: 1)
        #expect(probe.observed == [nil, nil])
    }

    @Test("Batch reuse does not depend on an iteration executing again")
    func decodedBatchCanBeReusedBeforePublication() throws {
        let results = GraphDeferredResults(limit: 3)
        let output = NodePort<Float>(name: "Output", kind: .Outlet)
        let binding = GraphDeferredNodeBinding(outputs: [output])
        let scope = results.defaultScope
        let state = scope.state(for: binding)
        for index in 0..<20 {
            let batch = results.admit()
            let segment = batch.appendSegment()
            segment.requests.append(.init(binding: binding, scope: scope, state: state,
                                          generation: binding.generation, body: { output.send(Float(index)) }))
            segment.markSubmitted()
            batch.finishRecording()
            segment.complete(.completed, generation: segment.generation)
            results.processReady()
        }
        #expect(output.value == nil)
        #expect(results.batchCreationCount == 1)
        state.publish(binding: binding)
        #expect(output.value == 19)
    }
}

extension DeferredGPUResultTests {
    @Test("Cancelling a scope's prepared outputs releases their storage without another execution")
    func cancellationReleasesPreparedStorage() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        var returns = 0
        var image: FabricImage? = .managed(texture: texture) { _ in returns += 1 }
        let output = NodePort<FabricImage>(name: "Output", kind: .Outlet)
        let binding = GraphDeferredNodeBinding(outputs: [output])
        let scope = GraphDeferredResultScope()
        let state = scope.state(for: binding)
        try binding.capture(in: state) { output.send(image) }
        image = nil
        #expect(returns == 0)
        binding.invalidate()
        #expect(returns == 1)
    }
}

private final class DeferredProcessorProbe: DeferredProbeNode {
    override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
}

extension DeferredGPUResultTests {
    @Test("A clean published processor still executes to deliver a ready result")
    func cleanProcessorDelivery() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let probe = DeferredProcessorProbe(context: harness.context)
        probe.output.published = true
        graph.addNode(probe)
        graph.rebuildPublishedParameterGroup()
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        try execute(renderer, graph: graph, harness: harness, frame: 0)
        #expect(!probe.isDirty)
        try execute(renderer, graph: graph, harness: harness, frame: 1)
        #expect(probe.observed == [nil, 10])
    }

    @Test("Completion in an earlier segment never changes an executing node's outputs")
    func continuationDoesNotPublishInline() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let probe = DeferredProbeNode(context: harness.context)
        probe.continueAfterRequest = true
        graph.addNode(probe)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        try execute(renderer, graph: graph, harness: harness, frame: 0)
        #expect(probe.output.value == nil)
        try execute(renderer, graph: graph, harness: harness, frame: 1)
        #expect(probe.output.value == 10)
    }

    @Test("An abandoned tail cannot publish, while its submitted prefix can deliver")
    func abandonedTail() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let probe = DeferredProbeNode(context: harness.context)
        probe.continueAfterRequest = true
        probe.addTailRequest = true
        graph.addNode(probe)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        try autoreleasepool {
            let commands = try #require(renderer.makeCommandBuffer())
            try renderer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(frameNumber: 0),
                                 renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
        }
        try execute(renderer, graph: graph, harness: harness, frame: 1)
        #expect(probe.output.value == 10)
    }

    @Test("Three full batches drain completions before admitting another frame")
    func boundedAdmissionMakesProgress() throws {
        let results = GraphDeferredResults(limit: 3)
        var segments: [GraphDeferredSegment] = []
        for _ in 0..<3 {
            let batch = results.admit()
            let segment = batch.appendSegment()
            segment.markSubmitted()
            batch.finishRecording()
            segments.append(segment)
        }
        let first = segments[0]
        let generation = first.generation
        DispatchQueue.global().async { first.complete(.completed, generation: generation) }
        let next = results.admit()
        #expect(results.batchCreationCount == 3)
        next.finishRecording()
        for segment in segments.dropFirst() { segment.complete(.completed, generation: segment.generation) }
        results.processReady()
    }
}

extension DeferredGPUResultTests {
    @Test("Retiring a binding releases removed ports and their last image values")
    func retiringBindingReleasesPorts() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        var returns = 0
        var image: FabricImage? = .managed(texture: texture) { _ in returns += 1 }
        var output: NodePort<FabricImage>? = NodePort(name: "Output", kind: .Outlet)
        let binding = GraphDeferredNodeBinding(outputs: [try #require(output)])
        let scope = GraphDeferredResultScope()
        let state = scope.state(for: binding)
        try binding.capture(in: state) { output?.send(image) }
        state.publish(binding: binding)
        image = nil
        output = nil
        #expect(returns == 0)
        binding.retire()
        #expect(returns == 1)
    }

    @Test("Decode errors are reported on the owner without partial publication")
    func decodeErrorDelivery() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let probe = DeferredProbeNode(context: harness.context)
        probe.failDecode = true
        graph.addNode(probe)
        let renderer = harness.graphRenderer(for: graph)
        let errors = RecordingErrorDelegate()
        renderer.errorDelegate = errors
        try renderer.startExecution()
        try execute(renderer, graph: graph, harness: harness, frame: 0)
        #expect(errors.reportedErrors.isEmpty)
        try execute(renderer, graph: graph, harness: harness, frame: 1)
        #expect(errors.reportedErrors.count == 1)
        #expect(probe.output.value == nil)
    }

    @Test("The public completion facade rejects buffers without graph context")
    func missingGraphContext() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let raw = try #require(harness.renderer.commandQueue.makeCommandBuffer())
        #expect(throws: GraphCompletionError.self) { try raw.addCompletion {} }
        #expect(raw.status == .notEnqueued)
        let commands = try #require(harness.renderer.makeCommandBuffer())
        #expect(throws: GraphCompletionError.self) { try commands.addCompletion {} }
        #expect(commands.status == .notEnqueued)
    }

    @Test("Stopping and restarting cannot deliver the old generation")
    func restartInvalidatesDelivery() throws {
        let harness = try #require(GraphExecutionTestHarness())
        let graph = Graph(context: harness.context)
        let probe = DeferredProbeNode(context: harness.context)
        graph.addNode(probe)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        try execute(renderer, graph: graph, harness: harness, frame: 0)
        try renderer.stopExecution()
        try renderer.startExecution()
        try execute(renderer, graph: graph, harness: harness, frame: 1)
        #expect(probe.output.value == nil)
    }
}
