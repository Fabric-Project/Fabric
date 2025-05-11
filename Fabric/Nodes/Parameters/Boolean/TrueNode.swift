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

class TrueNode : Node, NodeProtocol
{
    static let name = "True"
    static var nodeType = Node.NodeType.Parameter

    // Ports
    let outputBoolean: NodePort<Bool>

    override var ports: [any NodePortProtocol] { [outputBoolean] }
    
    required init(context: Context)
    {
        outputBoolean = NodePort<Bool>(name: "True" , kind: .Outlet)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case outputBooleanPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.outputBoolean, forKey: .outputBooleanPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.outputBoolean = try container.decode(NodePort<Bool>.self, forKey: .outputBooleanPort)
        
        try super.init(from: decoder)
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {

        self.outputBoolean.send( true )
     }
}
