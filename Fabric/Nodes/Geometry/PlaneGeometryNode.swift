//
//  PlaneGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Satin
import Foundation
import simd
import Metal

public class PlaneGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Plane Geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
        ("inputWidth", ParameterPort(parameter:FloatParameter("Width", 1.0, .inputfield))),
        ("inputHeight", ParameterPort(parameter:FloatParameter("Height", 1.0, .inputfield))),
        ("inputResolutionWidth", ParameterPort(parameter:IntParameter("Width", 1, .inputfield))),
        ("inputResolutionHeight", ParameterPort(parameter:IntParameter("Height", 1, .inputfield))),

        ] + ports
    }
    
    // Proxy Port
    public var inputWidth:ParameterPort<Float> { port(named: "inputWidth")  }
    public var inputHeight:ParameterPort<Float> { port(named: "inputHeight")  }
    public var inputResolutionWidth:ParameterPort<Int> { port(named: "inputResolutionWidth")  }
    public var inputResolutionHeight:ParameterPort<Int> { port(named: "inputResolutionHeight")  }
    
    public override var geometry: PlaneGeometry { _geometry }

    private let _geometry = PlaneGeometry(width: 1, height: 1, orientation: .xy)
    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputWidth.valueDidChange,
           let inputWidth = self.inputWidth.value
        {
            self.geometry.width = inputWidth
            shouldOutputGeometry = true
        }
        
        if self.inputHeight.valueDidChange,
           let height = self.inputHeight.value
        {
            self.geometry.height = height
            shouldOutputGeometry = true
        }
        
        if  self.inputResolutionWidth.valueDidChange || self.inputResolutionHeight.valueDidChange,
            let width = self.inputResolutionWidth.value,
            let height = self.inputResolutionHeight.value
        {
            self.geometry.resolution = simd_int2(Int32(width), Int32(height))
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}
