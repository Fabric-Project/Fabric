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
    public override class var nodeDescription: String { "Generates triangle geometry" }

    public let inputSize = ParameterPort(parameter:FloatParameter("Size", 1.0, .inputfield, "Size of the equilateral triangle in world units"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputSize", port: self.inputSize),
        ] + super.declaredPorts()
    }

    public override var geometry: TriangleGeometry { _geometry }
    
    private lazy var _geometry = TriangleGeometry(context:self.context, size: 1.0)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
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
