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
    public override var ports: [Port] {   [inputTexture] + super.ports }
    
    public override var material: BasicTextureMaterial {
        return _material
    }
    
    private var _material = BasicTextureMaterial()
    
    public required init(context:Context)
    {
        self.inputTexture = NodePort<EquatableTexture>(name: "Texture", kind: .Inlet)
        
        super.init(context: context)
        
//        self.material.flipped = true
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
    
    public override func evaluate(material:Material, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)
        
        if self.inputTexture.valueDidChange
        {
            self.material.texture =  self.inputTexture.value?.texture
            shouldOutput = true
        }
        
        return shouldOutput
    }
}
