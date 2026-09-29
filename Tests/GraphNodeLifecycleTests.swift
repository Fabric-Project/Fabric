import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

private class LifecycleRecordingNode: Node
{
    override class var name: String { "Lifecycle Recording" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Records lifecycle calls for tests" }

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [
            ("input", NodePort<Float>(name: "Input", kind: .Inlet)),
            ("output", NodePort<Float>(name: "Output", kind: .Outlet)),
        ]
    }

    var input: NodePort<Float> { port(named: "input") }
    var output: NodePort<Float> { port(named: "output") }

    private(set) var lifecycleCalls: [String] = []
    private(set) var executeCount = 0

    /// The lifecycle call, e.g. "stop", that throws instead of completing.
    var failingCall: String?

    private func throwIfFailing(_ call: String) throws
    {
        guard failingCall == call else { return }
        throw FabricError(.execution(.failed), severity: .recoverable, message: "Test \(call) failure.")
    }

    override func execute(renderer: GraphRenderer,
                          executionInfo: GraphExecutionInfo,
                          renderPassDescriptor: MTLRenderPassDescriptor,
                          commandBuffer: MTLCommandBuffer) throws
    {
        executeCount += 1
    }

    override func enableExecution(renderer: GraphRenderer) throws
    {
        lifecycleCalls.append("enable")
        try throwIfFailing("enable")
        try super.enableExecution(renderer: renderer)
    }

    override func startExecution(renderer: GraphRenderer) throws
    {
        lifecycleCalls.append("start")
        try throwIfFailing("start")
        try super.startExecution(renderer: renderer)
    }

    override func stopExecution(renderer: GraphRenderer) throws
    {
        lifecycleCalls.append("stop")
        try throwIfFailing("stop")
        try super.stopExecution(renderer: renderer)
    }

    override func disableExecution(renderer: GraphRenderer) throws
    {
        lifecycleCalls.append("disable")
        try throwIfFailing("disable")
        try super.disableExecution(renderer: renderer)
    }
}

private final class ConsumerLifecycleRecordingNode: LifecycleRecordingNode
{
    override class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
}

@Suite("Graph node lifecycle")
struct GraphNodeLifecycleTests
{
    @Test("An added node without connections is enabled but not started")
    func unconnectedNodeIsEnabledButNotStarted() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()

        let node = LifecycleRecordingNode(context: harness.context)
        graph.addNode(node)
        try renderer.synchronizeLifecycle()

        #expect(node.lifecycleCalls == ["enable"])
    }

    @Test("A first connection starts both nodes, the last disconnection stops them, and reconnecting starts them again")
    func connectingStartsAndDisconnectingStops() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let first = LifecycleRecordingNode(context: harness.context)
        let second = LifecycleRecordingNode(context: harness.context)
        graph.addNode(first)
        graph.addNode(second)
        try renderer.startExecution()

        let connection = try #require(graph.connect(first.output, to: second.input))
        try renderer.synchronizeLifecycle()
        #expect(first.lifecycleCalls == ["enable", "start"])
        #expect(second.lifecycleCalls == ["enable", "start"])

        graph.disconnect(connection)
        try renderer.synchronizeLifecycle()
        #expect(first.lifecycleCalls == ["enable", "start", "stop"])
        #expect(second.lifecycleCalls == ["enable", "start", "stop"])

        graph.connect(first.output, to: second.input)
        try renderer.synchronizeLifecycle()
        #expect(first.lifecycleCalls == ["enable", "start", "stop", "start"])
        #expect(second.lifecycleCalls == ["enable", "start", "stop", "start"])
    }

    @Test("Deleting a running node stops and disables it, and undo starts it again")
    func deletingAndRestoringARunningNode() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let undoManager = UndoManager()
        let node = ConsumerLifecycleRecordingNode(context: harness.context)
        graph.addNode(node)
        try renderer.startExecution()
        graph.undoManager = undoManager

        graph.delete(node: node)
        try renderer.synchronizeLifecycle()
        #expect(node.lifecycleCalls == ["enable", "start", "stop", "disable"])

        undoManager.undo()
        try renderer.synchronizeLifecycle()
        #expect(node.lifecycleCalls == ["enable", "start", "stop", "disable", "enable", "start"])
    }

    @Test("Duplicated connected nodes start")
    func duplicatedConnectedNodesStart() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let first = NumberBinaryOperator(context: harness.context)
        let second = NumberBinaryOperator(context: harness.context)
        graph.addNode(first)
        graph.addNode(second)
        graph.connect(first.outputNumber, to: second.inputNumber1)
        try renderer.startExecution()

        let duplicates = graph.duplicateNodes([first, second])
        try renderer.synchronizeLifecycle()

        #expect(duplicates.count == 2)
        #expect(duplicates.allSatisfy { $0.executionState == .started })
    }

    @Test("Embedding running nodes in a subgraph, and undoing it, does not restart them")
    func embeddingRunningNodesDoesNotRestartThem() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let undoManager = UndoManager()
        let first = LifecycleRecordingNode(context: harness.context)
        let second = LifecycleRecordingNode(context: harness.context)
        graph.addNode(first)
        graph.addNode(second)
        graph.connect(first.output, to: second.input)
        try renderer.startExecution()
        graph.undoManager = undoManager

        try graph.createSubgraph(from: [first, second], centeredOn: first, usingClass: SubgraphNode.self)
        try renderer.synchronizeLifecycle()
        #expect(first.lifecycleCalls == ["enable", "start"])
        #expect(second.lifecycleCalls == ["enable", "start"])

        undoManager.undo()
        try renderer.synchronizeLifecycle()
        #expect(first.lifecycleCalls == ["enable", "start"])
        #expect(second.lifecycleCalls == ["enable", "start"])
    }

    @Test("Deleting a subgraph node stops and disables the nodes inside it")
    func deletingSubgraphRetiresItsChildren() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let subgraphNode = SubgraphNode(context: harness.context)
        let child = ConsumerLifecycleRecordingNode(context: harness.context)
        subgraphNode.subGraph.addNode(child)
        graph.addNode(subgraphNode)
        try renderer.startExecution()
        #expect(child.lifecycleCalls == ["enable", "start"])

        graph.delete(node: subgraphNode)
        try renderer.synchronizeLifecycle()
        #expect(child.lifecycleCalls == ["enable", "start", "stop", "disable"])
    }

    @Test("An Iterator starts the nodes inside it without connections")
    func iteratorStartsUnconnectedChildren() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let iterator = IteratorNode(context: harness.context)
        let child = LifecycleRecordingNode(context: harness.context)
        iterator.subGraph.addNode(child)
        graph.addNode(iterator)

        try renderer.startExecution()

        #expect(child.lifecycleCalls == ["enable", "start"])
    }

    @Test("Publishing a port starts an unconnected node and unpublishing stops it")
    func publishingAPortStartsAnUnconnectedNode() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let node = LifecycleRecordingNode(context: harness.context)
        graph.addNode(node)
        try renderer.startExecution()

        node.output.published = true
        graph.rebuildPublishedParameterGroup()
        try renderer.synchronizeLifecycle()
        #expect(node.lifecycleCalls == ["enable", "start"])

        node.output.published = false
        graph.rebuildPublishedParameterGroup()
        try renderer.synchronizeLifecycle()
        #expect(node.lifecycleCalls == ["enable", "start", "stop"])
    }

    @Test("Nodes added while the renderer is stopped are enabled, and start when it starts")
    func nodesAddedWhileStoppedStartWhenItStarts() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        try renderer.startExecution()
        try renderer.stopExecution()

        let first = LifecycleRecordingNode(context: harness.context)
        let second = LifecycleRecordingNode(context: harness.context)
        graph.addNode(first)
        graph.addNode(second)
        graph.connect(first.output, to: second.input)
        try renderer.synchronizeLifecycle()
        #expect(first.lifecycleCalls == ["enable"])
        #expect(second.lifecycleCalls == ["enable"])

        try renderer.startExecution()
        #expect(first.lifecycleCalls == ["enable", "start"])
        #expect(second.lifecycleCalls == ["enable", "start"])
    }

    @Test("Frames without graph edits make no lifecycle calls")
    func unchangedFramesMakeNoLifecycleCalls() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let node = ConsumerLifecycleRecordingNode(context: harness.context)
        graph.addNode(node)
        try renderer.startExecution()

        try harness.execute(graph)
        try harness.execute(graph, frameNumber: 1)

        #expect(node.lifecycleCalls == ["enable", "start"])
    }

    @Test("A failing inner node is reported and does not keep its subgraph node or its siblings from starting")
    func failingInnerNodeDoesNotStrandItsSubgraph() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let errorDelegate = RecordingErrorDelegate()
        renderer.errorDelegate = errorDelegate
        let subgraphNode = SubgraphNode(context: harness.context)
        let failingChild = ConsumerLifecycleRecordingNode(context: harness.context)
        let healthyChild = ConsumerLifecycleRecordingNode(context: harness.context)
        failingChild.failingCall = "enable"
        subgraphNode.subGraph.addNode(failingChild)
        subgraphNode.subGraph.addNode(healthyChild)
        graph.addNode(subgraphNode)

        try renderer.startExecution()

        #expect(subgraphNode.executionState == .started)
        #expect(healthyChild.executionState == .started)
        #expect(failingChild.executionState == .disabled)
        #expect(!errorDelegate.reportedErrors.isEmpty)
    }

    @Test("Deleting a node whose stop throws still disables it and still deletes it")
    func deletingANodeWhoseStopThrowsStillDisablesIt() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let node = ConsumerLifecycleRecordingNode(context: harness.context)
        graph.addNode(node)
        try renderer.startExecution()

        node.failingCall = "stop"
        graph.delete(node: node)
        #expect(throws: FabricError.self) {
            try renderer.synchronizeLifecycle()
        }

        #expect(node.lifecycleCalls == ["enable", "start", "stop", "disable"])
        #expect(node.executionState == .disabled)
        #expect(!graph.nodes.contains { $0 === node })
    }

    @Test("Nodes execute only once their renderer has started them")
    func nodesExecuteOnlyWhileStarted() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let node = ConsumerLifecycleRecordingNode(context: harness.context)
        graph.addNode(node)

        try harness.execute(graph)
        #expect(node.executeCount == 0)

        try renderer.startExecution()
        try harness.execute(graph, frameNumber: 1)
        #expect(node.executeCount == 1)
    }

    @Test("A lifecycle failure during a frame is reported to the error delegate")
    func lifecycleFailureDuringAFrameIsReported() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let renderer = harness.graphRenderer(for: graph)
        let errorDelegate = RecordingErrorDelegate()
        renderer.errorDelegate = errorDelegate
        try renderer.startExecution()

        let node = ConsumerLifecycleRecordingNode(context: harness.context)
        node.failingCall = "start"
        graph.addNode(node)
        try harness.execute(graph)

        #expect(errorDelegate.reportedErrors.count == 1)
        #expect(node.executeCount == 0)
    }
}
