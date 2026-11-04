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
    let input = NodePort<Float>(name: "Input", kind: .Inlet)
    let output = NodePort<Float>(name: "Output", kind: .Outlet)

    override func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "input", port: self.input),
            PortDeclaration(key: "output", port: self.output),
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
