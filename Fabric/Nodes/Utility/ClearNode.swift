//
//  ClearNode.swift
//  Fabric
//

import Metal
import Satin
import simd

public final class ClearNode: Node
{
    override public class var name: String { "Clear" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Sets the initial render target clear color and optionally clears depth and stencil. Clear happens before scene rendering and does not participate in Render Order." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputClearColor", ParameterPort(parameter: Float4Parameter("Clear Color", .zero, .colorpicker, "Color used to initialize the render target"))),
            ("inputClearDepth", ParameterPort(parameter: BoolParameter("Clear Depth", true, .button, "Clear the depth attachment before scene rendering"))),
            ("inputClearStencil", ParameterPort(parameter: BoolParameter("Clear Stencil", false, .button, "Clear the stencil attachment before scene rendering"))),
        ]
    }

    public var inputClearColor: ParameterPort<simd_float4> { port(named: "inputClearColor") }
    public var inputClearDepth: ParameterPort<Bool> { port(named: "inputClearDepth") }
    public var inputClearStencil: ParameterPort<Bool> { port(named: "inputClearStencil") }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        renderer.renderEncoder.setClearColor(self.inputClearColor.value ?? .zero)
        renderer.renderEncoder.colorLoadAction = .clear
        renderer.renderEncoder.depthLoadAction = (self.inputClearDepth.value ?? true) ? .clear : .dontCare
        renderer.renderEncoder.stencilLoadAction = (self.inputClearStencil.value ?? false) ? .clear : .dontCare
    }
}
