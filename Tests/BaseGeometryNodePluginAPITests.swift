import Fabric
import Metal
import Satin
import Testing

private final class PluginGeometryNode: BaseGeometryNode
{
    override class var name: String { "Plugin Geometry" }
    override class var nodeTimeMode: Node.TimeMode { .TimeBase }

    let inputSize = ParameterPort(
        parameter: FloatParameter(
            "Size",
            1,
            .inputfield,
            "Geometry size"
        )
    )

    override func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputSize", port: self.inputSize),
        ] + super.declaredPorts()
    }

    override var geometry: Geometry { triangleGeometry }

    private lazy var triangleGeometry = TriangleGeometry(context: context)
    private(set) var executeInvocationCount = 0

    override func execute(
        renderer: GraphRenderer,
        executionInfo: GraphExecutionInfo,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) throws
    {
        executeInvocationCount += 1
        try super.execute(
            renderer: renderer,
            executionInfo: executionInfo,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer
        )
    }
}

@Suite("Base Geometry Node Plugin API")
struct BaseGeometryNodePluginAPITests
{
    @Test("An external-style subclass inherits ports and participates in execution")
    func externalSubclassUsesBaseGeometryLifecycle() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        guard let commandBuffer = harness.renderer.commandQueue.makeCommandBuffer() else
        {
            return
        }

        let node = PluginGeometryNode(context: harness.context)
        let renderPassDescriptor = MTLRenderPassDescriptor()

        try node.execute(
            renderer: harness.renderer,
            executionInfo: harness.makeExecutionInfo(),
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer
        )

        #expect(node.findPort(named: "inputSize", as: ParameterPort<Float>.self) != nil)
        #expect(node.inputPrimitiveType.value == "Triangle")
        #expect(node.primitiveType() == .triangle)
        #expect(node.outputGeometry.value === node.geometry)
        #expect(node.executeInvocationCount == 1)
    }
}
