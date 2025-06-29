//
//  BaseTextureComputeNode.swift
//  Fabric
//
//  Created by Anton Marini on 6/28/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

class BaseTexturePostProcessNode : Node, NodeProtocol
{
    class var name:String { "Base Texture Compute" }
    class var nodeType:Node.NodeType { .Texture }
    
    class PostMaterial: SourceMaterial {}

    
    // Parameters

    // Ports
    let inputTexturePort:NodePort<EquatableTexture>
    let outputTexturePort:NodePort<EquatableTexture>
    override var ports: [any NodePortProtocol] { super.ports + [inputTexturePort, outputTexturePort] }

    
    required init(context:Context)
    {
        self.inputTexturePort = NodePort<EquatableTexture>(name: "Texture", kind: .Inlet)
        self.outputTexturePort = NodePort<EquatableTexture>(name: "Texture", kind: .Outlet)

        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputTexturePort
        case outputTexturePort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputTexturePort, forKey: .inputTexturePort)
        try container.encode(self.outputTexturePort, forKey: .outputTexturePort)

        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
       
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
        self.inputTexturePort = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputTexturePort)
        self.outputTexturePort = try container.decode(NodePort<EquatableTexture>.self, forKey: .outputTexturePort)

        try super.init(from:decoder)
    }
    
//    override func execute(context:GraphExecutionContext,
//                          renderPassDescriptor: MTLRenderPassDescriptor,
//                          commandBuffer: MTLCommandBuffer)
//    {
//        
//        if let texture = self.texture
//        {
//            self.outputTexturePort.send( EquatableTexture(texture: texture) )
//        }
//        else
//        {
//            self.outputTexturePort.send( nil )
//        }
//    }
}
