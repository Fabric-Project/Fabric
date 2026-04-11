//
//  ShaderParameterNode.swift
//  Fabric
//
//  Created by Claude on 4/11/26.
//

import Foundation
import Satin
import Metal

/// Patching utility node for Shader ports. Passes through shader without modification.
/// Does not have editable inputs.
public class ShaderParameterNode: Node
{
    override public class var name: String { "Shader" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Patching utility for Shader. Does not have editable inputs." }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputShader", NodePort<Shader>(name: "Shader", kind: .Inlet, description: "Input shader")),
            ("outputShader", NodePort<Shader>(name: "Shader", kind: .Outlet, description: "Output shader")),
        ]
    }

    // Port Proxy
    public var inputShader: NodePort<Shader> { port(named: "inputShader") }
    public var outputShader: NodePort<Shader> { port(named: "outputShader") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.outputShader.send(self.inputShader.value)
    }
}
