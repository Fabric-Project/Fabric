import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

private final class ThrowingConsumerNode: Node
{
    override class var name: String { "Throwing Consumer" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Throws from execute for tests" }

    var severity: FabricErrorSeverity = .recoverable

    override func execute(renderer: GraphRenderer,
                          executionInfo: GraphExecutionInfo,
                          renderPassDescriptor: MTLRenderPassDescriptor,
                          commandBuffer: MTLCommandBuffer) throws
    {
        throw FabricError(.execution(.failed), severity: severity, message: "Test node failure.")
    }
}

private final class RecordingErrorDelegate: ErrorRenderDelegate
{
    private(set) var reportedErrors: [any Error] = []

    func renderer(_ renderer: Renderer, didFailWith error: any Error)
    {
        reportedErrors.append(error)
    }
}

@Suite("Graph renderer frame errors")
struct GraphRendererFrameErrorTests
{
    @Test("executeAndDraw draws the frame, then throws a recoverable error to its caller")
    func executeAndDrawDrawsThenThrowsRecoverableError() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        graph.addNode(ThrowingConsumerNode(context: harness.context))
        try harness.renderer.startExecution(graph: graph)

        let executionCountBeforeFrame = harness.renderer.executionCount
        #expect(throws: FabricError.self) {
            try harness.execute(graph: graph, executionInfo: harness.makeExecutionInfo(), drawScene: true)
        }

        #expect(harness.renderer.executionCount == executionCountBeforeFrame + 1)
    }

    @Test("The live draw path reports a recoverable error to the error delegate instead of throwing")
    func drawReportsRecoverableErrorWithoutThrowing() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        graph.addNode(ThrowingConsumerNode(context: harness.context))
        let renderer = GraphRenderer(context: harness.context, graph: graph)
        renderer.resize(size: (width: Float(harness.renderWidth), height: Float(harness.renderHeight)), scaleFactor: 1.0)
        let errorDelegate = RecordingErrorDelegate()
        renderer.errorDelegate = errorDelegate
        try renderer.startExecution(graph: graph)

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = try harness.makeTexture()
        let commandBuffer = try #require(renderer.commandQueue.makeCommandBuffer())
        renderer.planFrame(executionInfo: harness.makeExecutionInfo())

        try renderer.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        #expect(errorDelegate.reportedErrors.count == 1)
    }

    @Test("A fatal node error still throws from the frame")
    func fatalErrorThrows() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let node = ThrowingConsumerNode(context: harness.context)
        node.severity = .fatal
        graph.addNode(node)
        try harness.renderer.startExecution(graph: graph)

        #expect(throws: FabricError.self) {
            try harness.execute(graph: graph, executionInfo: harness.makeExecutionInfo(), drawScene: true)
        }
    }
}
