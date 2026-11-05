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
    override public class var name:String { "Transform Scale" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Scale a transform"}
    
    // Ports
    public let inputTransform = NodePort<simd_float4x4>.makeFresh(name: "Transform", kind: .Inlet, description: "4x4 transform matrix to scale")
    public let inputScale = ParameterPort(parameter: Float3Parameter("Scale", simd_float3(1, 1, 1), .inputfield, "XYZ scale factors to apply"))
    public let outputTransform = NodePort<simd_float4x4>(name: "Transform" , kind: .Outlet, description: "Scaled 4x4 transform matrix")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputTransform", port: self.inputTransform),
            PortDeclaration(key: "inputScale", port: self.inputScale),
            PortDeclaration(key: "outputTransform", port: self.outputTransform),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
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
