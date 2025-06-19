//
//  FalseNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/28/25.
//

import Foundation
import Satin
import simd
import Metal

public class FalseNode : Node, NodeProtocol
{
    public static let name = "False"
    public static var nodeType = Node.NodeType.Parameter(parameterType: .Boolean)

    // Ports
    public let outputBoolean: NodePort<Bool>
    public override var ports: [any NodePortProtocol] { super.ports +  [self.outputBoolean] }
    
    public required init(context: Context)
    {
        self.outputBoolean = NodePort<Bool>(name: "False" , kind: .Outlet)
        
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
            
    public override func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
        self.outputBoolean.send( false )
    }
}
