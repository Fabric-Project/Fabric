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

public class TranslateTransformNode : Node
{
    override public class var name:String { "Transform Translate" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Translate a transform"}
    
    // Ports
    public let inputTransform = NodePort<simd_float4x4>.makeFresh(name: "Transform", kind: .Inlet, description: "4x4 transform matrix to translate")
    public let inputTranslation = ParameterPort(parameter: Float3Parameter("Translation", simd_float3(0, 0, 0), .inputfield, "XYZ translation offset to apply"))
    public let outputTransform = NodePort<simd_float4x4>(name: "Transform" , kind: .Outlet, description: "Translated 4x4 transform matrix")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputTransform", port: self.inputTransform),
            PortDeclaration(key: "inputTranslation", port: self.inputTranslation),
            PortDeclaration(key: "outputTransform", port: self.outputTransform),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputTranslation.valueDidChange || self.inputTransform.valueDidChange,
           let inputTransform = self.inputTransform.value,
           let inputTranslation = self.inputTranslation.value
        {
            let translationTransform = translationMatrix3f(inputTranslation)
            
            self.outputTransform.send( simd_mul(inputTransform, translationTransform) )
        }
    }
}
