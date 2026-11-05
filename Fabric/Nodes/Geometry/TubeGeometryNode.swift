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

public class TubeGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Tube Geometry" }
    public override class var nodeDescription: String { "Generates tube geometry" }

    public let inputRadius = ParameterPort(parameter:FloatParameter("Radius", 0.25, .inputfield, "Radius of the tube in world units"))
    public let inputHeight = ParameterPort(parameter:FloatParameter("Height", 0.75, .inputfield, "Height of the tube in world units"))
    public let inputStartAngle = ParameterPort(parameter:FloatParameter("Start Angle", 0.0, .inputfield, "Starting angle of the tube arc in degrees"))
    public let inputEndAngle = ParameterPort(parameter:FloatParameter("End Angle", 90.0, .inputfield, "Ending angle of the tube arc in degrees"))
    public let inputAngularResolution = ParameterPort(parameter:IntParameter("Angular Segments", 20, .inputfield, "Number of segments around the tube circumference"))
    public let inputVerticalResolution = ParameterPort(parameter:IntParameter("Vertical Segments", 5, .inputfield, "Number of segments along the tube height"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputRadius", port: self.inputRadius),
            PortDeclaration(key: "inputHeight", port: self.inputHeight),
            PortDeclaration(key: "inputStartAngle", port: self.inputStartAngle),
            PortDeclaration(key: "inputEndAngle", port: self.inputEndAngle),
            PortDeclaration(key: "inputAngularResolution", port: self.inputAngularResolution),
            PortDeclaration(key: "inputVerticalResolution", port: self.inputVerticalResolution),
        ] + super.declaredPorts()
    }

    public override var geometry: TubeGeometry { _geometry }

    private lazy var _geometry = TubeGeometry(context:self.context, radius: 0.25, height: 0.75, startAngle: 0.0, endAngle: degToRad(90.0), angularResolution: 20, verticalResolution: 5)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputRadius.valueDidChange,
           let inputRadius = self.inputRadius.value
        {
            self.geometry.radius = degToRad(inputRadius)
            shouldOutputGeometry = true
        }
        
        if self.inputHeight.valueDidChange,
           let inputHeight = self.inputHeight.value
        {
            self.geometry.height = inputHeight
            shouldOutputGeometry = true
        }
        
        if self.inputStartAngle.valueDidChange,
           let inputAngle = self.inputStartAngle.value
        {
            self.geometry.startAngle = degToRad(inputAngle)
            shouldOutputGeometry = true
        }
        
        if self.inputEndAngle.valueDidChange,
           let inputAngle = self.inputEndAngle.value
        {
            self.geometry.endAngle = degToRad(inputAngle)
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
