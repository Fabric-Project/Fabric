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

public class SphereGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Sphere Geometry" }
    public override class var nodeDescription: String { "Generates sphere geometry" }

    public let inputRadius = ParameterPort(parameter:FloatParameter("Radius", 1.0, .inputfield, "Radius of the sphere in world units"))
    public let inputAngularResolution = ParameterPort(parameter:IntParameter("Angular Segments", 60, .inputfield, "Number of segments around the circumference"))
    public let inputVerticalResolution = ParameterPort(parameter:IntParameter("Vertical Segments", 30, .inputfield, "Number of segments from pole to pole"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputRadius", port: self.inputRadius),
            PortDeclaration(key: "inputAngularResolution", port: self.inputAngularResolution),
            PortDeclaration(key: "inputVerticalResolution", port: self.inputVerticalResolution),
        ] + super.declaredPorts()
    }

    public override var geometry: SphereGeometry { _geometry }

    private lazy var _geometry = SphereGeometry(context:self.context, radius: 1.0, angularResolution: 60, verticalResolution: 30)
    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputRadius.valueDidChange,
           let inputRadius = self.inputRadius.value
        {
            self.geometry.radius = inputRadius
            shouldOutputGeometry = true
        }
        
        if self.inputAngularResolution.valueDidChange,
           let inputAngularResolution = self.inputAngularResolution.value
        {
            self.geometry.angularResolution = inputAngularResolution
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
