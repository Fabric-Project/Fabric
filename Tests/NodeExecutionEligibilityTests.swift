import Testing
import Fabric
import Satin
import Metal

/// Imports Fabric as a plugin does, without @testable access.
private final class ExternalPendingResultNode: Node {
    override class var name: String { "External Pending Result" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Plugin-style deferred result eligibility" }
    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)] {
        super.registerPorts(context: context) + [
            ("input", NodePort<Float>(name: "Input", kind: .Inlet)),
            ("output", NodePort<Float>(name: "Output", kind: .Outlet))
        ]
    }
    var hasPendingResult = false
    override var isDirty: Bool { super.isDirty || hasPendingResult }
}

@Suite("Plugin execution eligibility")
struct NodeExecutionEligibilityTests {
    @Test("A plugin can extend eligibility without replacing input dirty tracking")
    func pendingResultEligibility() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let node = ExternalPendingResultNode(context: context)
        let originalPorts = node.ports.map(\.id)
        node.reorderPorts(Array(node.ports.reversed()))
        #expect(node.ports.map(\.id) == Array(originalPorts.reversed()))
        #expect(node.isDirty)
        node.markClean()
        #expect(!node.isDirty)
        node.hasPendingResult = true
        #expect(node.isDirty)
        node.markClean()
        #expect(node.isDirty)
        node.hasPendingResult = false
        #expect(!node.isDirty)
        node.markDirty()
        #expect(node.isDirty)
    }
}
