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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
        ("inputRadius",  ParameterPort(parameter:FloatParameter("Radius", 1.0, .inputfield))),
        ("inputHeight",  ParameterPort(parameter:FloatParameter("Height", 2.0, .inputfield))),
        ("inputAngularResolution",  ParameterPort(parameter:IntParameter("Angular Resolution", 30, .inputfield))),
        ("inputVerticalResolution",  ParameterPort(parameter:IntParameter("Vertical Resolution", 30, .inputfield))),
            
        ] + ports
    }
    
    // Proxy Port
    public var inputRadius:ParameterPort<Float> { port(named: "inputRadius")  }
    public var inputHeight:ParameterPort<Float> { port(named: "inputHeight")  }
    public var inputAngularResolution:ParameterPort<Int> { port(named: "inputAngularResolution") }
    public var inputVerticalResolution:ParameterPort<Int> { port(named: "inputVerticalResolution")  }

    public override var geometry: CapsuleGeometry { _geometry }

    private let _geometry = CapsuleGeometry(radius: 1.0, height: 2.0, angularResolution: 30, radialResolution: 30, verticalResolution: 30)

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
