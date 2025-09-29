//
//  BasicTextureMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//


import Foundation
import Satin
import simd
import Metal

public class BasicTextureMaterialNode : BasicColorMaterialNode
{
    public override class var name:String {  "Texture Material" }

    // Ports
    public let inputTexture:NodePort<EquatableTexture>
    public override var ports: [any NodePortProtocol] {   [inputTexture] + super.ports }
    
    public override var material: BasicTextureMaterial {
        return _material
    }
    
    private var _material = BasicTextureMaterial()
    
    public required init(context:Context)
    {
        self.inputTexture = NodePort<EquatableTexture>(name: "Texture", kind: .Inlet)
        
        super.init(context: context)
        
        self.material.flipped = true
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputTexturePort
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputTexturePort)

        try super.init(from: decoder)

        self.material.flipped = true
    }

    public override func encode(to encoder: any Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.inputTexture, forKey: .inputTexturePort)
        try super.encode(to: encoder)
    }
    
    public override func evaluate(material:Material, atTime:TimeInterval)
    {
        super.evaluate(material: material, atTime: atTime)
        material.depthWriteEnabled = self.inputWriteDepth.value
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.evaluate(material: self.material, atTime: context.timing.time)
        
        if self.inputTexture.valueDidChange
        {
            self.material.texture =  self.inputTexture.value?.texture
        }
        
        self.outputMaterial.send(self.material)
    }
}
