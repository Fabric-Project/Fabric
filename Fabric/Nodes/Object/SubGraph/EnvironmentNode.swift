//
//  EnvironmentNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/14/25.
//

import Foundation
import Satin
import simd
import Metal

public class EnvironmentNode: SubgraphNode
{
    override public class var name:String { "Environment Node" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Subgraph }
    
    // Ports:
    public let inputEnvironmentTexture:NodePort<EquatableTexture>
    public override var ports: [AnyPort] {[inputEnvironmentTexture] + super.ports}
   
    public required init(context: Context)
    {
        self.inputEnvironmentTexture = NodePort<EquatableTexture>(name: "Environment Texture", kind: .Inlet)

        super.init(context: context)
        
        self.subGraph.scene = IBLScene()
    }

    enum CodingKeys : String, CodingKey
    {
        case inputEnvironmentTexturePort
    }

    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputEnvironmentTexture, forKey: .inputEnvironmentTexturePort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputEnvironmentTexture = try container.decode(NodePort<EquatableTexture>.self , forKey:.inputEnvironmentTexturePort)

        try super.init(from: decoder)
        
        self.subGraph.scene = IBLScene()
    }
    
    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: any MTLCommandBuffer)
    {
        if self.inputEnvironmentTexture.valueDidChange,
           let environmentTexture = self.inputEnvironmentTexture.value,
           let iblScene = self.subGraph.scene as? IBLScene
        {
            iblScene.setEnvironment(texture: environmentTexture.texture)
        }
        
        super.execute(context: context, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }
}
