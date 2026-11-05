//
//  BoxGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/25/25.
//
import Satin
import Foundation
import simd
import Metal

public class ConeGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Cone Geometry" }
    public override class var nodeDescription: String { "Generates cone geometry" }

    public let inputRadius = ParameterPort(parameter:FloatParameter("Radius", 1.0, .inputfield, "Radius of the cone base in world units"))
    public let inputHeight = ParameterPort(parameter:FloatParameter("Height", 2.0, .inputfield, "Height of the cone from base to tip in world units"))
    public let inputAngularResolution = ParameterPort(parameter:IntParameter("Angular Segments", 20, .inputfield, "Number of segments around the cone circumference"))
    public let inputRadialResolution = ParameterPort(parameter:IntParameter("Radial Segments", 2, .inputfield, "Number of segments from center to edge on the base"))
    public let inputVerticalResolution = ParameterPort(parameter:IntParameter("Vertical Segments", 2, .inputfield, "Number of segments along the cone height"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputRadius", port: self.inputRadius),
            PortDeclaration(key: "inputHeight", port: self.inputHeight),
            PortDeclaration(key: "inputAngularResolution", port: self.inputAngularResolution),
            PortDeclaration(key: "inputRadialResolution", port: self.inputRadialResolution),
            PortDeclaration(key: "inputVerticalResolution", port: self.inputVerticalResolution),
        ] + super.declaredPorts()
    }

    public override var geometry: ConeGeometry { _geometry }

    private lazy var _geometry = ConeGeometry(context:self.context, radius: 1.0, height: 2.0, angularResolution: 20, radialResolution: 2, verticalResolution: 2)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputRadius.valueDidChange,
           let inputRadius = self.inputRadius.value
        {
            self.geometry.radius = inputRadius
            shouldOutputGeometry = true
        }
        
        if self.inputHeight.valueDidChange,
            let inputHeight = self.inputHeight.value
        {
            self.geometry.height = inputHeight
            shouldOutputGeometry = true
        }
        
        if self.inputAngularResolution.valueDidChange,
            let inputAngularResolution = self.inputAngularResolution.value
        {
            self.geometry.angularResolution = inputAngularResolution
            shouldOutputGeometry = true
        }
        
        if self.inputRadialResolution.valueDidChange,
            let inputRadialResolution = self.inputRadialResolution.value
        {
            self.geometry.radialResolution = inputRadialResolution
            shouldOutputGeometry = true
        }
        
        if self.inputVerticalResolution.valueDidChange,
           let inputVerticalResolution = self.inputVerticalResolution.value
        {
            self.geometry.verticalResolution = inputVerticalResolution
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}
