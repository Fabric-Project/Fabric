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
    override public class var nodeDescription: String { "Provides basic Image rendering"}

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
                    ("inputTexture", NodePort<EquatableTexture>(name: "Texture", kind: .Inlet) ),
                ] + ports
    }
    
    public var inputTexture:NodePort<EquatableTexture> { port(named: "inputTexture") }
    
    public override var material: BasicTextureMaterial {
        return _material
    }
    
    private var _material = BasicTextureMaterial()

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
