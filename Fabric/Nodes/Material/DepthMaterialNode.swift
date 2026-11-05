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

    public let inputNear = ParameterPort(parameter:FloatParameter("Near", 0.001, 0.0, 1000.0, .slider, "Near clipping distance for depth visualization"))
    public let inputFar = ParameterPort(parameter:FloatParameter("Far", 500.0, 0.0, 1000.0, .slider, "Far clipping distance for depth visualization"))
    public let inputInvert = ParameterPort(parameter:BoolParameter("Invert", false, .toggle, "When enabled, inverts the depth gradient"))
    public let inputColor = ParameterPort(parameter:BoolParameter("Color", true, .toggle, "When enabled, renders depth as color gradient"))
    public let inputPointSize = ParameterPort(parameter:FloatParameter("Point Size", 1.0, 0.5, 64.0, .slider, "Point Size") )

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputNear", port: self.inputNear),
            PortDeclaration(key: "inputFar", port: self.inputFar),
            PortDeclaration(key: "inputInvert", port: self.inputInvert),
            PortDeclaration(key: "inputColor", port: self.inputColor),
            PortDeclaration(key: "inputPointSize", port: self.inputPointSize),
        ] + super.declaredPorts()
    }

    public override var material: DepthMaterial {
        return _material
    }
    
    private lazy var _material = DepthMaterial(context: self.context)
    
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

        if self.inputPointSize.valueDidChange,
           let inputPointSize = self.inputPointSize.value
        {
            shouldOutput = true
            self.material.pointSize = inputPointSize
        }
        
        return shouldOutput
    }
}
