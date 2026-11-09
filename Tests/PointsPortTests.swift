import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

private func publish(_ port: Fabric.Port, in graph: Graph)
{
    port.published = true
    graph.rebuildPublishedParameterGroup()
}

/// Publishes new Points on every execution, one point at (frame, 0, 0), as a GPU producer would:
/// a fresh buffer each time, never a write into one already sent.
private final class PublishingPointsProviderNode: Node
{
    override class var name: String { "Publishing Points Provider" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Test provider that publishes new points every frame." }

    var output: NodePort<Satin.Points> { port(named: "output") }
    private(set) var published: [Satin.Points] = []

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [
            ("output", NodePort<Satin.Points>(name: "Points", kind: .Outlet)),
        ]
    }

    override func execute(renderer: GraphRenderer,
                          executionInfo: GraphExecutionInfo,
                          renderPassDescriptor: MTLRenderPassDescriptor,
                          commandBuffer: MTLCommandBuffer)
    {
        let x = Float(published.count)
        guard let points = try? Satin.Points(positions: [[x, 0, 0]], allocator: context.gpuAllocator) else { return }
        published.append(points)
        output.send(points, force: true)
    }
}

@Suite("Points port")
struct PointsPortTests
{
    @Test("Points round-trips through its port type name")
    func portTypeNameRoundTrips()
    {
        #expect(PortType.Points.rawValue == "Points")
        #expect(PortType(rawValue: "Points") == .Points)
        #expect(PortType.Points.type == Satin.Points.self)
    }

    @Test("Points round-trips through a boxed port value")
    func boxedValueRoundTrips() throws
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let points = try Satin.Points(positions: [[1, 2, 3]], allocator: context.gpuAllocator)

        let boxed = points.toPortValue()
        #expect(boxed == .Points(points))
        #expect(Satin.Points.fromPortValue(boxed) == points)
        #expect(Satin.Points.fromPortValue(.Float(1)) == nil)
    }

    @Test("Sample and Hold keeps drawing the version it held while the producer publishes new ones")
    func sampleAndHoldKeepsItsPublishedVersion() throws
    {
        guard let harness = GraphExecutionTestHarness(renderWidth: 64, renderHeight: 64) else { return }

        let graph = Graph(context: harness.context)
        let producer = PublishingPointsProviderNode(context: harness.context)
        let hold = SampleAndHoldNode(context: harness.context, portType: .Virtual)
        graph.addNode(producer)
        graph.addNode(hold)

        graph.connect(producer.output, to: hold.port(named: "inputValue", as: NodePort<PortValue>.self))
        let heldOutput = hold.port(named: "outputValue", as: NodePort<PortValue>.self)
        publish(heldOutput, in: graph)

        try harness.graphRenderer(for: graph).startExecution()

        try harness.execute(graph, frameNumber: 0)
        let first = try #require(producer.published.first)
        #expect(heldOutput.value == .Points(first))

        hold.inputSample.value = false
        try harness.execute(graph, frameNumber: 1)
        try harness.execute(graph, frameNumber: 2)

        // The producer moved on; the held value is still the first version, contents unchanged.
        #expect(producer.published.count == 3)
        #expect(heldOutput.value == .Points(first))
        let held = first.position.buffer.contents().bindMemory(to: simd_float3.self, capacity: 1)
        #expect(held[0] == simd_float3(0, 0, 0))
        #expect(Set(producer.published.map(\.version)).count == 3)
    }
}
