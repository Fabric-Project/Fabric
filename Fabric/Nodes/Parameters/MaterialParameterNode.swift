//
//  MaterialParameterNode.swift
//  Fabric
//
//  Created by Claude on 4/11/26.
//

import Foundation
import Satin
import Metal

/// Patching utility node for Material ports. Passes through material without modification.
/// Does not have editable inputs.
public class MaterialParameterNode: Node
{
    override public class var name: String { "Material" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Patching utility for Material. Does not have editable inputs." }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputMaterial", NodePort<Material>(name: "Material", kind: .Inlet, description: "Input material")),
            ("outputMaterial", NodePort<Material>(name: "Material", kind: .Outlet, description: "Output material")),
        ]
    }

    // Port Proxy
    public var inputMaterial: NodePort<Material> { port(named: "inputMaterial") }
    public var outputMaterial: NodePort<Material> { port(named: "outputMaterial") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.outputMaterial.send(self.inputMaterial.value)
    }
}
