//
//  UVMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 11/17/25.
//

import Foundation
import Satin
import simd
import Metal

public class UVMaterialNode : BaseMaterialNode
{
    public override class var name:String {  "UV Material" }
    override public class var nodeDescription: String { "Provides visualization of underlying geometry UV coordinates."}
    
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
                    ("inputPointSize", ParameterPort(parameter:FloatParameter("Point Size", 1.0, 0.5, 64.0, .slider, "Point Size") ) ),

                ] + ports
    }
    
    public var inputPointSize:ParameterPort<Float>   { port(named: "inputPointSize") }

    public override var material: UVColorMaterial {
        return _material
    }
    
    private lazy var _material = UVColorMaterial(context:self.context)

    public override func evaluate(material:Material, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)

        if self.inputPointSize.valueDidChange,
           let inputPointSize = self.inputPointSize.value
        {
            shouldOutput = true
            self.material.pointSize = inputPointSize
        }
        
        return shouldOutput
    }
}
