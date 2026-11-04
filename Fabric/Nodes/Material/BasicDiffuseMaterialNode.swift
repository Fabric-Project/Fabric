//
//  BasicDiffuseMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import Satin
import simd
import Metal

public class BasicDiffuseMaterialNode : BasicColorMaterialNode
{
    public override class var name:String {  "Diffuse Material" }
    override public class var nodeDescription: String { "Provides basic color rendering, with simple lighting."}

    public let inputHardness = ParameterPort(parameter:FloatParameter("Hardness", 1, 0, 1, .slider, "Controls diffuse falloff sharpness (0 = soft, 1 = hard)"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputHardness", port: self.inputHardness),
        ] + super.declaredPorts()
    }

    public override var material: BasicDiffuseMaterial {
        return _material
    }
    
    private lazy var _material = BasicDiffuseMaterial(context: self.context)
    
    public override func evaluate(material:Material, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)
        
        if self.inputHardness.valueDidChange,
           let hardness = self.inputHardness.value
        {
            self.material.hardness = hardness
            shouldOutput = true
        }
        
        return shouldOutput
    }
}
