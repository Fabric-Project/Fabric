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
    override public class var nodeDescription: String { "Provides basic color rendering."}

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
                    ("inputColor", ParameterPort(parameter:Float4Parameter("Color", .one, .zero, .one, .colorpicker, "Flat color applied to the entire surface (RGBA)")) ),
                    ("inputPointSize", ParameterPort(parameter:FloatParameter("Point Size", 1.0, 0.5, 64.0, .slider, "Point Size") ) ),

                ] + ports
    }
    
    public var inputColor:ParameterPort<simd_float4> { port(named: "inputColor") }
    public var inputPointSize:ParameterPort<Float>   { port(named: "inputPointSize") }

    public override var material: BasicColorMaterial {
        return _material
    }
    
    private lazy var _material = BasicColorMaterial(context: self.context)
    
    public override func evaluate(material:Material, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)
        
        if self.inputColor.valueDidChange,
           let color = self.inputColor.value
        {
            shouldOutput = true
            self.material.color = color
        }
        
        if self.inputPointSize.valueDidChange,
           let inputPointSize = self.inputPointSize.value
        {
            shouldOutput = true
            self.material.pointSize = inputPointSize
        }
        
        return shouldOutput
    }
}
