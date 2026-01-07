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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
        ("inputRadius",  ParameterPort(parameter:FloatParameter("Radius", 1.0, .inputfield))),
        ("inputHeight",  ParameterPort(parameter:FloatParameter("Height", 2.0, .inputfield))),
        ("inputAngularResolution",  ParameterPort(parameter:IntParameter("Angular Resolution", 20, .inputfield))),
        ("inputRadialResolution",  ParameterPort(parameter:IntParameter("Radial Resolution", 2, .inputfield))),
        ("inputVerticalResolution",  ParameterPort(parameter:IntParameter("Vertical Resolution", 2, .inputfield))),

        ] + ports
    }
    
    // Proxy Port
    public var inputRadius:ParameterPort<Float> { port(named: "inputRadius")  }
    public var inputHeight:ParameterPort<Float> { port(named: "inputHeight")  }
    public var inputAngularResolution:ParameterPort<Int> { port(named: "inputAngularResolution") }
    public var inputRadialResolution:ParameterPort<Int> { port(named: "inputRadialResolution")  }
    public var inputVerticalResolution:ParameterPort<Int> { port(named: "inputVerticalResolution")  }

    public override var geometry: ConeGeometry { _geometry }

    private let _geometry = ConeGeometry(radius: 1.0, height: 2.0, angularResolution: 20, radialResolution: 2, verticalResolution: 2)

    override public func evaluate(geometry: SatinGeometry, atTime: TimeInterval) -> Bool
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
