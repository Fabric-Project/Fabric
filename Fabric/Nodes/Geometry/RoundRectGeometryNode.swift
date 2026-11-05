//
//  RoundRectGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/3/25.
//

import Satin
import Foundation
import simd
import Metal

public class RoundRectGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Round Rect Geometry" }
    public override class var nodeDescription: String { "Generates rounded rectangle geometry" }

    public let inputWidth = ParameterPort(parameter:FloatParameter("Width", 1.0, .inputfield, "Width of the rectangle in world units"))
    public let inputHeight = ParameterPort(parameter:FloatParameter("Height", 1.0, .inputfield, "Height of the rectangle in world units"))
    public let inputRadius = ParameterPort(parameter:FloatParameter("Radius", 1.0, .inputfield, "Corner radius for the rounded edges in world units"))
    public let inputResolutionWidth = ParameterPort(parameter:IntParameter("Angular Segments", 1, .inputfield, "Number of segments for the corner curves"))
    public let inputResolutionHeight = ParameterPort(parameter:IntParameter("Radial Segments", 1, .inputfield, "Number of radial segments from center to edge"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputWidth", port: self.inputWidth),
            PortDeclaration(key: "inputHeight", port: self.inputHeight),
            PortDeclaration(key: "inputRadius", port: self.inputRadius),
            PortDeclaration(key: "inputResolutionWidth", port: self.inputResolutionWidth),
            PortDeclaration(key: "inputResolutionHeight", port: self.inputResolutionHeight),
        ] + super.declaredPorts()
    }

    public override var geometry: RoundedRectGeometry { _geometry }

    private lazy var _geometry = RoundedRectGeometry(context:self.context, width: 1, height: 1, radius: 0.2, angularResolution: 32, radialResolution: 32)
    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputWidth.valueDidChange || self.inputHeight.valueDidChange,
           let inputWidth = self.inputWidth.value,
           let inputHeight = self.inputHeight.value
        {
            self.geometry.size = simd_float2( inputWidth, inputHeight)
            shouldOutputGeometry = true
        }
        
        if self.inputRadius.valueDidChange,
           let inputRadius = self.inputRadius.value
        {
            self.geometry.radius = max(0.0001, inputRadius)
            shouldOutputGeometry = true
        }
        
        if  self.inputResolutionWidth.valueDidChange || self.inputResolutionHeight.valueDidChange,
            let inputResolutionWidth = self.inputResolutionWidth.value,
            let inputResolutionHeight = self.inputResolutionHeight.value
        {
            self.geometry.angularResolution = inputResolutionWidth
            self.geometry.radialResolution = inputResolutionHeight
            
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}
