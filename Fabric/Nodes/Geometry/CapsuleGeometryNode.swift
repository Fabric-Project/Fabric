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

public class CapsuleGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Capsule Geometry" }
    public override class var nodeDescription: String { "Generates capsule geometry" }

    public let inputRadius = ParameterPort(parameter:FloatParameter("Radius", 1.0, .inputfield, "Radius of the capsule cylinder and end caps in world units"))
    public let inputHeight = ParameterPort(parameter:FloatParameter("Height", 2.0, .inputfield, "Height of the cylindrical section in world units"))
    public let inputAngularResolution = ParameterPort(parameter:IntParameter("Angular Segments", 30, .inputfield, "Number of segments around the capsule circumference"))
    public let inputVerticalResolution = ParameterPort(parameter:IntParameter("Vertical Segments", 30, .inputfield, "Number of segments along the capsule height"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputRadius", port: self.inputRadius),
            PortDeclaration(key: "inputHeight", port: self.inputHeight),
            PortDeclaration(key: "inputAngularResolution", port: self.inputAngularResolution),
            PortDeclaration(key: "inputVerticalResolution", port: self.inputVerticalResolution),
        ] + super.declaredPorts()
    }

    public override var geometry: CapsuleGeometry { _geometry }

    private lazy var _geometry = CapsuleGeometry(context:self.context, radius: 1.0, height: 2.0, angularResolution: 30, radialResolution: 30, verticalResolution: 30)

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
        
        if self.inputVerticalResolution.valueDidChange,
           let inputVerticalResolution = self.inputVerticalResolution.value
        {
            self.geometry.verticalResolution = inputVerticalResolution
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}
