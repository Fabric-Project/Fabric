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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
        ("inputRadius",  ParameterPort(parameter:FloatParameter("inputRadius", 1.0, .inputfield))),
        ("inputResolution",  ParameterPort(parameter:IntParameter("inputResolution", 1, .inputfield))),

        ] + ports
    }
    
    // Proxy Port
    public var inputRadius:ParameterPort<Float> { port(named: "inputRadius")  }
    public var inputResolution:ParameterPort<Int> { port(named: "inputResolution")  }

    public override var geometry: IcoSphereGeometry { _geometry }
    private let _geometry = IcoSphereGeometry(radius: 1.0, resolution: 1)
    
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
