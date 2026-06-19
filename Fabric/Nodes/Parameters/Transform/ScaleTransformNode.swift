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

public class ScaleTransformNode : Node
{
    override public class var name:String { "Make Scale Transform" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Scale a Transform"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputTransform", NodePort<simd_float4x4>(name: "Transform" , kind: .Inlet, description: "4x4 transform matrix to scale")),
            ("inputScale", NodePort<simd_float3>(name: "Scale" , kind: .Inlet, description: "XYZ scale factors to apply")),
            ("outputTransform", NodePort<simd_float4x4>(name: "Transform" , kind: .Outlet, description: "Scaled 4x4 transform matrix")),
        ]
    }
    
    // Port Proxy
    public var inputTransform:NodePort<simd_float4x4> { port(named: "inputTransform") }
    public var inputScale:NodePort<simd_float3> { port(named: "inputScale") }
    public var outputTransform:NodePort<simd_float4x4> { port(named: "outputTransform") }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputScale.valueDidChange || self.inputTransform.valueDidChange,
           let inputTransform = self.inputTransform.value,
           let inputScale = self.inputScale.value
        {
            let scaleTransform = scaleMatrix3f(inputScale)
            
            self.outputTransform.send( simd_mul(inputTransform, scaleTransform) )
        }
    }
}
