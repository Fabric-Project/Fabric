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

public class DecomposeTransformNode : Node
{
    override public class var name:String { "Decompose A Transform" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Decompose a Transform into a Translation, Scale and Rotation"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputTransform", NodePort<simd_float4x4>(name: "Transform" , kind: .Inlet)),
            ("outputTranslation", NodePort<simd_float3>(name: "Translation" , kind: .Outlet)),
            ("outputScale", NodePort<simd_float3>(name: "Scale" , kind: .Outlet)),
            ("outputRotation", NodePort<simd_float4>(name: "Rotation" , kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputTransform:NodePort<simd_float4x4> { port(named: "inputTransform") }
    public var outputTranslation:NodePort<simd_float3> { port(named: "outputTranslation") }
    public var outputScale:NodePort<simd_float3> { port(named: "outputScale") }
    public var outputRotation:NodePort<simd_float4> { port(named: "outputRotation") }

    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if  self.inputTransform.valueDidChange,
           let inputTransform = self.inputTransform.value
        {

            let translation = simd_make_float3(inputTransform.columns.3)
            let sx = inputTransform.columns.0
            let sy = inputTransform.columns.1
            let sz = inputTransform.columns.2
            
            let scale = simd_make_float3(simd_length(sx), simd_length(sy), simd_length(sz))
            let rx = simd_make_float3(sx) / scale.x
            let ry = simd_make_float3(sy) / scale.y
            let rz = simd_make_float3(sz) / scale.z
            
            let orientation = simd_quatf(simd_float3x3(rx, ry, rz)).normalized
            
            self.outputTranslation.send(translation)
            self.outputScale.send(scale)
            self.outputRotation.send(orientation.vector)
        }
    }
}
