//
//  ArrayQueueNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/19/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class ArrayQueueNode<Value : Equatable & FabricDescription> : Node
{
    public override var name:String { "\(Value.fabricDescription) Queue" }
    public override var nodeType:Node.NodeType { .Parameter(parameterType: .Array) }

    let inputSizeParam:FloatParameter
    override public var inputParameters: [any Parameter] { [self.inputSizeParam] + super.inputParameters}

    let inputPort:NodePort<Value>
    let outputPort:NodePort<ContiguousArray<Value>>
    override public var ports:[AnyPort] {  [inputPort, outputPort] + super.ports}

    private var queue:ContiguousArray<Value> = []
    
    required public init(context:Context)
    {
        self.inputPort = NodePort<Value>(name: "Value", kind: .Inlet)
        self.inputSizeParam = FloatParameter("Size", 0, .inputfield)
        
        self.outputPort = NodePort<ContiguousArray<Value>>(name: "Array", kind: .Outlet)
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputPort
        case inputSizeParam
        case outputPort
    }
    
    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputPort, forKey: .inputPort)
        try container.encode(self.inputSizeParam, forKey: .inputSizeParam)
        try container.encode(self.outputPort, forKey: .outputPort)

        try super.encode(to: encoder)
    }
    
    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
       
        self.inputPort = try container.decode(NodePort<Value>.self, forKey: .inputPort)
        self.inputSizeParam = try container.decode(FloatParameter.self, forKey: .inputSizeParam)
        self.outputPort = try container.decode(NodePort< ContiguousArray<Value> >.self, forKey: .outputPort)
        
        try super.init(from:decoder)
    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        
        if self.inputSizeParam.valueDidChange
        {
            self.queue = ContiguousArray( self.queue.prefix(Int(self.inputSizeParam.value)) )
        }
        
        if self.inputPort.valueDidChange, let value = self.inputPort.value
        {
            self.queue.insert(value, at: 0)
            
            self.queue = ContiguousArray( self.queue.prefix(Int(self.inputSizeParam.value)) )

            self.outputPort.send( self.queue )
        }
    }
}
