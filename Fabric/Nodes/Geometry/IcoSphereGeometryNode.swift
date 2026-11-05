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

public class IcoSphereGeometryNode : BaseGeometryNode
{
    public override class var name:String { "IcoSphere Geometry" }
    public override class var nodeDescription: String { "Generates icosphere geometry" }

    public let inputRadius = ParameterPort(parameter:FloatParameter("Radius", 1.0, .inputfield, "Radius of the icosphere in world units"))
    public let inputResolution = ParameterPort(parameter:IntParameter("Segments", 1, .inputfield, "Subdivision level for mesh detail (higher = more triangles)"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputRadius", port: self.inputRadius),
            PortDeclaration(key: "inputResolution", port: self.inputResolution),
        ] + super.declaredPorts()
    }

    public override var geometry: IcoSphereGeometry { _geometry }
    private lazy var _geometry = IcoSphereGeometry(context:self.context, radius: 1.0, resolution: 1)
    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputRadius.valueDidChange,
           let inputRadius = self.inputRadius.value
        {
            self.geometry.radius = inputRadius
            shouldOutputGeometry = true
        }
                
        if  self.inputResolution.valueDidChange,
            let inputResolution = self.inputResolution.value
        {
            self.geometry.resolution = inputResolution
            shouldOutputGeometry = true
        }
       
        return shouldOutputGeometry
     }
}
