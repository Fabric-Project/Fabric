//
//  TrueNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/28/25.
//

import Foundation
import Satin
import simd
import Metal

public class TrueNode : Node
{
    override public static var name:String { "True" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Boolean) }

    // Ports
    public let outputBoolean: NodePort<Bool>

    public override var ports: [AnyPort] { [outputBoolean] + super.ports }
    
    public required init(context: Context)
    {
        outputBoolean = NodePort<Bool>(name: "True" , kind: .Outlet)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case outputBooleanPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.outputBoolean, forKey: .outputBooleanPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.outputBoolean = try container.decode(NodePort<Bool>.self, forKey: .outputBooleanPort)
        
        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {

        self.outputBoolean.send( true )
     }
}
