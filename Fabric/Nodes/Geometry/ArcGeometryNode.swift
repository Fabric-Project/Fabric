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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
            ("inputInnerRadius",  ParameterPort(parameter:FloatParameter("Inner Radius", 0.25, .inputfield))),
            ("inputOuteradius",  ParameterPort(parameter:FloatParameter("Outer Radius", 0.75, .inputfield))),
            ("inputStartAngle",  ParameterPort(parameter:FloatParameter("Start Angle", 0.0, .inputfield))),
            ("inputEndAngle",  ParameterPort(parameter:FloatParameter("End Angle", 90.0, .inputfield))),
        ("inputAngularResolution",  ParameterPort(parameter:IntParameter("Angular Resolution", 20, .inputfield))),
        ("inputRadialResolution",  ParameterPort(parameter:IntParameter("Radial Resolution", 5, .inputfield))),
            
        ] + ports
    }
    
    // Proxy Port
    public var inputInnerRadius:ParameterPort<Float> { port(named: "inputInnerRadius")  }
    public var inputOuteradius:ParameterPort<Float> { port(named: "inputOuteradius")  }
    public var inputStartAngle:ParameterPort<Float> { port(named: "inputStartAngle")  }
    public var inputEndAngle:ParameterPort<Float> { port(named: "inputEndAngle")  }
    public var inputAngularResolution:ParameterPort<Int> { port(named: "inputAngularResolution") }
    public var inputRadialResolution:ParameterPort<Int> { port(named: "inputRadialResolution")  }

    public override var geometry: ArcGeometry { _geometry }

    private let _geometry = ArcGeometry(radius: (inner: 0.25, outer:0.75),
                                        angle: (start:0.0, end:90.0), res: (angular:20, radial:5))

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
            self.geometry.startAngle = inputAngle
            shouldOutputGeometry = true
        }
        
        if self.inputEndAngle.valueDidChange,
           let inputAngle = self.inputEndAngle.value
        {
            self.geometry.endAngle = inputAngle
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
