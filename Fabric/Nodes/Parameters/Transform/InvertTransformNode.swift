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

public class InvertTransformNode : Node
{
    override public class var name:String { "Transform Invert" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Invert a Transform"}
    
    // Ports
    public let inputTransform = NodePort<simd_float4x4>.makeFresh(name: "Transform", kind: .Inlet, description: "4x4 transform matrix to invert")
    public let outputTransform = NodePort<simd_float4x4>(name: "Transform" , kind: .Outlet, description: "Inverted 4x4 transform matrix")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputTransform", port: self.inputTransform),
            PortDeclaration(key: "outputTransform", port: self.outputTransform),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputTransform.valueDidChange,
           let inputTransform = self.inputTransform.value
        {
            self.outputTransform.send( inputTransform.inverse )
        }
    }
}
