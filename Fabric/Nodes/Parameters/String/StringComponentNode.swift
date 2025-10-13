//
//  StringComponentNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class StringComponentNode : Node
{
    override public static var name:String { "String Components" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }

    // TODO: add character set menu to choose component separation strategy
    
    let inputPort:NodePort<String>
    let outputPort:NodePort<ContiguousArray<String>>
    override public var ports:[AnyPort] {  [inputPort, outputPort] + super.ports}

    private var url: URL? = nil
    private var string: String? = nil
    
    required public init(context:Context)
    {
        self.inputPort = NodePort<String>(name: "String", kind: .Inlet)
        self.outputPort = NodePort<ContiguousArray<String>>(name: "Lines", kind: .Outlet)
        
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
       
        self.inputPort = try container.decode(NodePort<String>.self, forKey: .inputPort)
        self.outputPort = try container.decode(NodePort<ContiguousArray<String>>.self, forKey: .outputPort)
        
        try super.init(from:decoder)
    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange
        {
            if let string = self.inputPort.value
            {
                self.outputPort.send( ContiguousArray<String>(string.components(separatedBy: .newlines)) )
            }
            else
            {
                self.outputPort.send( nil )
            }
        }
    }
}
