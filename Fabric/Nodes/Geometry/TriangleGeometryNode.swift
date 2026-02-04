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

public class TriangleGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Triangle Geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
        ("inputSize",  ParameterPort(parameter:FloatParameter("Size", 1.0, .inputfield, "Size of the equilateral triangle in world units"))),

        ] + ports
    }
    
    // Proxy Port
    public var inputSize:ParameterPort<Float> { port(named: "inputSize")  }

    public override var geometry: TriangleGeometry { _geometry }
    
    private let _geometry = TriangleGeometry(size: 1.0)

    override public func evaluate(geometry: SatinGeometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputSize.valueDidChange,
           let inputSize = self.inputSize.value
        {
            self._geometry.size = inputSize
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}
