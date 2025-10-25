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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
                    ("inputHardness", ParameterPort(parameter:FloatParameter("Hardness", 1, 0, 1, .slider)) ),
                ] + ports
    }
    
    public var inputHardness:ParameterPort<Float> { port(named: "inputHardness") }
    
    public override var material: BasicDiffuseMaterial {
        return _material
    }
    
    private var _material = BasicDiffuseMaterial()
    
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
