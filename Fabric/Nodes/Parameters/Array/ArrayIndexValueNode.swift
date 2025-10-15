//
//  ArrayIndexValueNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class ArrayIndexValueNode<Value : Equatable & FabricDescription> : Node
{
    public override class var name:String {"\(Value.fabricDescription) Value at Array Index" }
    public override class var nodeType:Node.NodeType { .Parameter(parameterType: .Array) }

    let inputIndexParam:FloatParameter
    override public var inputParameters: [any Parameter] { [self.inputIndexParam] + super.inputParameters}

    let inputPort:NodePort<ContiguousArray<Value>>
    let outputPort:NodePort<Value>
    override public var ports:[AnyPort] {  [inputPort, outputPort] + super.ports}
    
    required public init(context:Context)
    {
        self.inputPort = NodePort<ContiguousArray<Value>>(name: "Array", kind: .Inlet)
        self.inputIndexParam = FloatParameter("Index", 0, .inputfield)
        
        self.outputPort = NodePort<Value>(name: "Value", kind: .Outlet)
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputPort
        case inputIndexParam
        case outputPort
    }
    
    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputPort, forKey: .inputPort)
        try container.encode(self.inputIndexParam, forKey: .inputIndexParam)
        try container.encode(self.outputPort, forKey: .outputPort)

        try super.encode(to: encoder)
    }
    
    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
       
        self.inputPort = try container.decode(NodePort<ContiguousArray<Value>>.self, forKey: .inputPort)
        self.inputIndexParam = try container.decode(FloatParameter.self, forKey: .inputIndexParam)
        self.outputPort = try container.decode(NodePort<Value>.self, forKey: .outputPort)
        
        try super.init(from:decoder)
    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange || self.inputIndexParam.valueDidChange
        {
            let index = max( 0, Int(self.inputIndexParam.value) )
            
            if let array = self.inputPort.value
            {
                let val = array[index]
                self.outputPort.send( val )
            }
            
            else
            {
                self.outputPort.send( nil )
            }
        }
    }
}
