//
//  RoundRectGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/3/25.
//

import Satin
import Foundation
import simd
import Metal

public class RoundRectGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Round Rect Geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
        ("inputWidth", ParameterPort(parameter:FloatParameter("Width", 1.0, .inputfield))),
        ("inputHeight", ParameterPort(parameter:FloatParameter("Height", 1.0, .inputfield))),
        ("inputRadius", ParameterPort(parameter:FloatParameter("Radius", 1.0, .inputfield))),
        ("inputResolutionWidth", ParameterPort(parameter:IntParameter("Width", 1, .inputfield))),
        ("inputResolutionHeight", ParameterPort(parameter:IntParameter("Height", 1, .inputfield))),

        ] + ports
    }
    
    // Proxy Port
    public var inputWidth:ParameterPort<Float> { port(named: "inputWidth")  }
    public var inputHeight:ParameterPort<Float> { port(named: "inputHeight")  }
    public var inputRadius:ParameterPort<Float> { port(named: "inputRadius")  }
    public var inputResolutionWidth:ParameterPort<Int> { port(named: "inputResolutionWidth")  }
    public var inputResolutionHeight:ParameterPort<Int> { port(named: "inputResolutionHeight")  }
    
   
    public override var geometry: RoundedRectGeometry { _geometry }

    private let _geometry = RoundedRectGeometry(width: 1, height: 1, radius: 0.2, angularResolution: 32, radialResolution: 32)
    
    override public func evaluate(geometry: SatinGeometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputWidth.valueDidChange || self.inputHeight.valueDidChange,
           let inputWidth = self.inputWidth.value,
           let inputHeight = self.inputHeight.value
        {
            self.geometry.size = simd_float2( inputWidth, inputHeight)
            shouldOutputGeometry = true
        }
        
        if self.inputRadius.valueDidChange,
           let inputRadius = self.inputRadius.value
        {
            self.geometry.radius = max(0.0001, inputRadius)
            shouldOutputGeometry = true
        }
        
        if  self.inputResolutionWidth.valueDidChange || self.inputResolutionHeight.valueDidChange,
            let inputResolutionWidth = self.inputResolutionWidth.value,
            let inputResolutionHeight = self.inputResolutionHeight.value
        {
            self.geometry.angularResolution = inputResolutionWidth
            self.geometry.radialResolution = inputResolutionHeight
            
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}
