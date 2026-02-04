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

public class RotateTransformNode : Node
{
    override public class var name:String { "Rotate A Transform" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Rotate a Transform"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputTransform", NodePort<simd_float4x4>(name: "Transform" , kind: .Inlet, description: "4x4 transform matrix to rotate")),
            ("inputRotation", NodePort<simd_float4>(name: "Rotation" , kind: .Inlet, description: "Quaternion rotation to apply")),
            ("outputTransform", NodePort<simd_float4x4>(name: "Transform" , kind: .Outlet, description: "Rotated 4x4 transform matrix")),
        ]
    }
    
    // Port Proxy
    public var inputTransform:NodePort<simd_float4x4> { port(named: "inputTransform") }
    public var inputRotation:NodePort<simd_float4> { port(named: "inputRotation") }
    public var outputTransform:NodePort<simd_float4x4> { port(named: "outputTransform") }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputRotation.valueDidChange || self.inputTransform.valueDidChange,
           let inputTransform = self.inputTransform.value,
           let inputRotation = self.inputRotation.value
        {
            let rotationTransform = simd_float4x4( simd_quatf(vector:inputRotation) )
            
            self.outputTransform.send( simd_mul(inputTransform, rotationTransform) )
        }
    }
}
