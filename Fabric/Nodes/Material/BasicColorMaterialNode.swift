//
//  BasicColorMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//

import Foundation
import Satin
import simd
import Metal

public class BasicColorMaterialNode : BaseMaterialNode
{
    public override class var name:String {  "Color Material" }
    
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
                    ("inputColor", ParameterPort(parameter:Float4Parameter("Color", .one, .zero, .one, .colorpicker)) ),
                ] + ports
    }
    
    public var inputColor:ParameterPort<simd_float4> { port(named: "inputColor") }
    
    public override var material: BasicColorMaterial {
        return _material
    }
    
    private var _material = BasicColorMaterial()
    
    public override func evaluate(material:Material, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)
        
        if self.inputColor.valueDidChange,
           let color = self.inputColor.value
        {
            shouldOutput = true
            self.material.color = color
        }
        
        return shouldOutput
    }
}
