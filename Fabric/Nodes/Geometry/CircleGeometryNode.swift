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

public class CircleGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Circle Geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
        ("inputSize",  ParameterPort(parameter:FloatParameter("Size", 1.0, .inputfield, "Radius of the circle in world units"))),

        ] + ports
    }
    
    // Proxy Port
    public var inputSize:ParameterPort<Float> { port(named: "inputSize")  }
   
    public override var geometry: CircleGeometry { _geometry }
    
    private let _geometry = CircleGeometry(radius: 1.0, angularResolution: 60, radialResolution: 1)
    
    override public func evaluate(geometry: SatinGeometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputSize.valueDidChange,
           let inputSize = self.inputSize.value
        {
            self._geometry.radius = inputSize
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}
