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
    public override class var name:String {  "Image Material" }
    override public class var nodeDescription: String { "Provides basic Image rendering"}

    public let inputTexture = NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Texture image to apply to the material surface")

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputTexture", port: self.inputTexture),
        ] + super.declaredPorts()
    }

    public override var material: BasicTextureMaterial {
        return _material
    }
    
    private lazy var _material = BasicTextureMaterial(context: self.context)

    public override func evaluate(material:Material, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)
        
        if self.inputTexture.valueDidChange
        {
            self.material.texture =  self.inputTexture.value?.texture
            self.material.textureTransform = self.inputTexture.value?.textureTransform ?? matrix_identity_float4x4
            shouldOutput = true
        }
        
        return shouldOutput
    }
}
