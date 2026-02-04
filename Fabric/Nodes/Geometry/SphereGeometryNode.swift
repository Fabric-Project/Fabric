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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
        ("inputRadius", ParameterPort(parameter:FloatParameter("Radius", 1.0, .inputfield, "Radius of the sphere in world units"))),
        ("inputAngularResolution", ParameterPort(parameter:IntParameter("Angular Resolution", 60, .inputfield, "Number of segments around the circumference"))),
        ("inputVerticalResolution", ParameterPort(parameter:IntParameter("Vertical Resolution", 30, .inputfield, "Number of segments from pole to pole"))),

        ] + ports
    }
    
    // Proxy Port
    public var inputRadius:ParameterPort<Float> { port(named: "inputRadius")  }
    public var inputAngularResolution:ParameterPort<Int> { port(named: "inputAngularResolution")  }
    public var inputVerticalResolution:ParameterPort<Int> { port(named: "inputVerticalResolution")  }

    public override var geometry: SphereGeometry { _geometry }

    private let _geometry = SphereGeometry(radius: 1.0, angularResolution: 60, verticalResolution: 30)
    
    override public func evaluate(geometry: SatinGeometry, atTime: TimeInterval) -> Bool
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
