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

public class TransposeTransformNode : Node
{
    override public class var name:String { "Transform Transpose" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Transpose a transform"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputTransform", PortType.Transform.makeFreshPort(name: "Transform", kind: .Inlet, description: "4x4 transform matrix to transpose")),
            ("outputTransform", NodePort<simd_float4x4>(name: "Transform" , kind: .Outlet, description: "Transposed 4x4 transform matrix")),
        ]
    }
    
    // Port Proxy
    public var inputTransform: NodePort<simd_float4x4> { _inputTransform }
    private var _inputTransform: NodePort<simd_float4x4>!
    public var inputTranslation: NodePort<simd_float3> { _inputTranslation }
    private var _inputTranslation: NodePort<simd_float3>!
    public var outputTransform: NodePort<simd_float4x4> { _outputTransform }
    private var _outputTransform: NodePort<simd_float4x4>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._inputTransform = findPort(named: "inputTransform")
        self._inputTranslation = findPort(named: "inputTranslation")
        self._outputTransform = findPort(named: "outputTransform")
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputTranslation.valueDidChange || self.inputTransform.valueDidChange,
           let inputTransform = self.inputTransform.value
        {
            self.outputTransform.send( inputTransform.transpose )
        }
    }
}
