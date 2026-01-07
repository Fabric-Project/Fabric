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

public class TorusGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Torus Geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
            ("inputMinorRadius",  ParameterPort(parameter:FloatParameter("Minor Radius", 5.0, .inputfield))),
            ("inputMajorRadius",  ParameterPort(parameter:FloatParameter("Major Radius", 0.25, .inputfield))),
            ("inputMinorResolution",  ParameterPort(parameter:IntParameter("Minor Resolution", 20, .inputfield))),
            ("inputMajorResolution",  ParameterPort(parameter:IntParameter("Major Resolution", 20, .inputfield))),

        ] + ports
    }
    
    // Proxy Port
    public var inputMinorRadius:ParameterPort<Float> { port(named: "inputMinorRadius")  }
    public var inputMajorRadius:ParameterPort<Float> { port(named: "inputMajorRadius")  }
    public var inputMinorResolution:ParameterPort<Int> { port(named: "inputMinorResolution") }
    public var inputMajorResolution:ParameterPort<Int> { port(named: "inputMajorResolution")  }

    public override var geometry: TorusGeometry { _geometry }

    private let _geometry = TorusGeometry(minorRadius: 5.0, majorRadius: 0.25, minorResolution: 20, majorResolution: 20)

    override public func evaluate(geometry: SatinGeometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputMinorRadius.valueDidChange,
           let inputRadius = self.inputMinorRadius.value
        {
            self.geometry.minorRadius = degToRad(inputRadius)
            shouldOutputGeometry = true
        }
        
        if self.inputMajorRadius.valueDidChange,
           let inputMajorRadius = self.inputMajorRadius.value
        {
            self.geometry.majorRadius = inputMajorRadius
            shouldOutputGeometry = true
        }
                
        if self.inputMajorResolution.valueDidChange,
            let inputMajorResolution = self.inputMajorResolution.value
        {
            self.geometry.majorResolution = inputMajorResolution
            shouldOutputGeometry = true
        }
        
        if self.inputMinorResolution.valueDidChange,
            let inputMinorResolution = self.inputMinorResolution.value
        {
            self.geometry.minorResolution = inputMinorResolution
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}
