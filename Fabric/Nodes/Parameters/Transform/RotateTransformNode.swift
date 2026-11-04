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
    override public class var name:String { "Transform Rotate" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Rotate a transform"}
    
    // Ports
    public let inputTransform = NodePort<simd_float4x4>.makeFresh(name: "Transform", kind: .Inlet, description: "4x4 transform matrix to rotate")
    public let inputRotation = ParameterPort(parameter: Float4Parameter("Rotation", simd_float4(0, 0, 0, 1), .inputfield, "Quaternion rotation to apply (X, Y, Z, W)"))
    public let outputTransform = NodePort<simd_float4x4>(name: "Transform" , kind: .Outlet, description: "Rotated 4x4 transform matrix")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputTransform", port: self.inputTransform),
            PortDeclaration(key: "inputRotation", port: self.inputRotation),
            PortDeclaration(key: "outputTransform", port: self.outputTransform),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputRotation.valueDidChange || self.inputTransform.valueDidChange,
           let inputTransform = self.inputTransform.value,
           let inputRotation = self.inputRotation.value
        {
            let rotationTransform = simd_float4x4( simd_quatf(safeVector:inputRotation) )
            
            self.outputTransform.send( simd_mul(inputTransform, rotationTransform) )
        }
    }
}
