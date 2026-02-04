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

public class RoundBoxGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Round Box Geometry" }

    
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
        ("inputSize", ParameterPort(parameter:Float3Parameter("Size", .zero, .inputfield, "Dimensions of the box (width, height, depth) in world units"))),
        ("inputRadius", ParameterPort(parameter:FloatParameter("Radius", 1.0, .inputfield, "Corner radius for the rounded edges in world units"))),
        ("inputResolution", ParameterPort(parameter:IntParameter("Resolution", 1, .inputfield, "Number of segments for the rounded corners"))),

        ] + ports
    }
    
    // Proxy Port
    public var inputSize:ParameterPort<simd_float3> { port(named: "inputSize")  }
    public var inputRadius:ParameterPort<Float> { port(named: "inputRadius")  }
    public var inputResolution:ParameterPort<Int> { port(named: "inputResolution")  }
       
    public override var geometry: RoundedBoxGeometry { _geometry }

    private let _geometry = RoundedBoxGeometry(size: .init(repeating: 2.0), radius: 0.25, resolution: 3)
    
    override public func evaluate(geometry: SatinGeometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)
      
        if self.inputSize.valueDidChange,
           let inputSize = self.inputSize.value
        {
            self.geometry.size = inputSize
            shouldOutputGeometry = true
        }
        
        if self.inputRadius.valueDidChange,
           let inputRadius = self.inputRadius.value
        {
            self.geometry.radius = max(0.0001, inputRadius)
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
