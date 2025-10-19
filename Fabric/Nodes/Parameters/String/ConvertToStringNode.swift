//
//  ConvertToStringNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class ConvertToStringNode : Node
{
    override public static var name:String { "Convert To String" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }

    let inputPort:NodePort<AnyLoggable>
    let outputPort:NodePort<String>
    override public var ports:[Port] {  [inputPort, outputPort] + super.ports}

    private var url: URL? = nil
    private var string: String? = nil
    
    required public init(context:Context)
    {
        self.inputPort = NodePort<AnyLoggable>(name: "Any", kind: .Inlet)
        self.outputPort = NodePort<String>(name: "String", kind: .Outlet)
        
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
       
        self.inputPort = try container.decode(NodePort<AnyLoggable>.self, forKey: .inputPort)
        self.outputPort = try container.decode(NodePort<String>.self, forKey: .outputPort)
        
        try super.init(from:decoder)
    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange,
           let value = self.inputPort.value
        {
            self.outputPort.send( String(describing:value) )
        }
    }
}
