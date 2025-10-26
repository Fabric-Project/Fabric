//
//  DepthMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//


import Foundation
import Satin
import simd
import Metal

public class DepthMaterialNode : BaseMaterialNode
{
    public override class var name:String {  "Depth Material" }
    override public class var nodeDescription: String { "Visualizes Geometry depth as seen by the active camera."}

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
                    ("inputNear", ParameterPort(parameter:FloatParameter("Near", 0.001, 0.0, 1000.0, .slider)) ),
                    ("inputFar", ParameterPort(parameter:FloatParameter("Far", 500.0, 0.0, 1000.0, .slider)) ),
                    ("inputInvert", ParameterPort(parameter:BoolParameter("Invert", false, .toggle)) ),
                    ("inputColor", ParameterPort(parameter:BoolParameter("Color", true, .toggle)) ),
                ] + ports
    }
    
    public var inputNear:ParameterPort<Float> { port(named: "inputNear") }
    public var inputFar:ParameterPort<Float> { port(named: "inputFar") }
    public var inputInvert:ParameterPort<Bool> { port(named: "inputInvert") }
    public var inputColor:ParameterPort<Bool> { port(named: "inputColor") }

    public override var material: DepthMaterial {
        return _material
    }
    
    private var _material = DepthMaterial()
    
    public override func evaluate(material: Material, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)
        
        if self.inputFar.valueDidChange,
           let far = self.inputFar.value
        {
            self.material.far = far
            shouldOutput = true
        }
        
        if self.inputNear.valueDidChange,
           let near = self.inputNear.value
        {
            self.material.near = near
            shouldOutput = true
        }
        
        if self.inputInvert.valueDidChange,
           let invert = self.inputInvert.value
        {
            self.material.invert = invert
            shouldOutput = true
        }
        
        if self.inputColor.valueDidChange,
           let color = self.inputColor.value
        {
            self.material.color = color
            shouldOutput = true
        }
        
        return shouldOutput
    }
}
