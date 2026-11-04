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

public class ArcGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Arc Geometry" }
    public override class var nodeDescription: String { "Generates arc geometry" }

    public let inputInnerRadius = ParameterPort(parameter:FloatParameter("Inner Radius", 0.25, .inputfield, "Inner radius of the arc ring in world units"))
    public let inputOuteradius = ParameterPort(parameter:FloatParameter("Outer Radius", 0.75, .inputfield, "Outer radius of the arc ring in world units"))
    public let inputStartAngle = ParameterPort(parameter:FloatParameter("Start Angle", 0.0, .inputfield, "Starting angle of the arc in degrees"))
    public let inputEndAngle = ParameterPort(parameter:FloatParameter("End Angle", 90.0, .inputfield, "Ending angle of the arc in degrees"))
    public let inputAngularResolution = ParameterPort(parameter:IntParameter("Angular Segments", 20, .inputfield, "Number of segments along the arc curve"))
    public let inputRadialResolution = ParameterPort(parameter:IntParameter("Radial Segments", 5, .inputfield, "Number of segments from inner to outer radius"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputInnerRadius", port: self.inputInnerRadius),
            PortDeclaration(key: "inputOuteradius", port: self.inputOuteradius),
            PortDeclaration(key: "inputStartAngle", port: self.inputStartAngle),
            PortDeclaration(key: "inputEndAngle", port: self.inputEndAngle),
            PortDeclaration(key: "inputAngularResolution", port: self.inputAngularResolution),
            PortDeclaration(key: "inputRadialResolution", port: self.inputRadialResolution),
        ] + super.declaredPorts()
    }

    public override var geometry: ArcGeometry { _geometry }

    private lazy var _geometry = ArcGeometry(context:self.context, radius: (inner: 0.25, outer:0.75),
                                        angle: (start:0.0, end:degToRad(90.0)), res: (angular:20, radial:5))

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputInnerRadius.valueDidChange,
           let inputRadius = self.inputInnerRadius.value
        {
            self.geometry.innerRadius = inputRadius
            shouldOutputGeometry = true
        }
        
        if self.inputOuteradius.valueDidChange,
           let inputRadius = self.inputOuteradius.value
        {
            self.geometry.outerRadius = inputRadius
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
        
        if self.inputRadialResolution.valueDidChange,
           let inputRadialResolution = self.inputRadialResolution.value
        {
            self.geometry.radialResolution = inputRadialResolution
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}
