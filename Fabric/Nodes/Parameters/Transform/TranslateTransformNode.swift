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
    override public class var name:String { "Translate A Transform" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Translate a Transform"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputTransform", NodePort<simd_float4x4>(name: "Transform" , kind: .Inlet)),
            ("inputTranslation", NodePort<simd_float3>(name: "Translation" , kind: .Inlet)),
            ("outputTransform", NodePort<simd_float4x4>(name: "Transform" , kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputTransform:NodePort<simd_float4x4> { port(named: "inputTransform") }
    public var inputTranslation:NodePort<simd_float3> { port(named: "inputTranslation") }
    public var outputTransform:NodePort<simd_float4x4> { port(named: "outputTransform") }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
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
