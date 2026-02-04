//
//  NumberNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/2/25.
//

import Foundation
import Satin
import simd
import Metal

public class IdentityTransformNode : Node
{
    override public class var name:String { "Identity Transform" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provide a Identity Transform"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("outputTransform", NodePort<simd_float4x4>(name: "Transform" , kind: .Outlet, description: "Identity 4x4 transform matrix")),
        ]
    }
    
    // Port Proxy
    public var outputTransform:NodePort<simd_float4x4> { port(named: "outputTransform") }

    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.outputTransform.send( matrix_identity_float4x4 )
    }
}
