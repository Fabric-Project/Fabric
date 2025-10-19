//
//  ArrayCountNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//


import Foundation
import Satin
import simd
import Metal
import MetalKit

public class ArrayCountNode<Value : Equatable & FabricDescription> : Node
{
    public override class var name:String { "\(Value.fabricDescription) Array Count" }
    public override class var nodeType:Node.NodeType { .Parameter(parameterType: .Array) }

    // TODO: add character set menu to choose component separation strategy
    
    let inputPort:NodePort<ContiguousArray<Value>>
    let outputPort:NodePort<Float>
    override public var ports:[Port] {  [inputPort, outputPort] + super.ports}

    private var url: URL? = nil
    private var string: String? = nil
    
    required public init(context:Context)
    {
        self.inputPort = NodePort<ContiguousArray<Value>>(name: "Array", kind: .Inlet)
        self.outputPort = NodePort<Float>(name: "Count", kind: .Outlet)
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputPort
        case outputPort
    }
    
    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputPort, forKey: .inputPort)
        try container.encode(self.outputPort, forKey: .outputPort)

        try super.encode(to: encoder)
    }
    
    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
       
        self.inputPort = try container.decode(NodePort<ContiguousArray<Value>>.self, forKey: .inputPort)
        self.outputPort = try container.decode(NodePort<Float>.self, forKey: .outputPort)
        
        try super.init(from:decoder)
    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange
        {
            if let array = self.inputPort.value
            {
                self.outputPort.send( Float(array.count) )
            }
            
            else
            {
                self.outputPort.send( nil )
            }
        }
    }
}
