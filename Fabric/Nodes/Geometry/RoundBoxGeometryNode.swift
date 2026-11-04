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
    public override class var nodeDescription: String { "Generates rounded box geometry" }


    public let inputSize = ParameterPort(parameter:Float3Parameter("Size", .zero, .inputfield, "Dimensions of the box (width, height, depth) in world units"))
    public let inputRadius = ParameterPort(parameter:FloatParameter("Radius", 1.0, .inputfield, "Corner radius for the rounded edges in world units"))
    public let inputResolution = ParameterPort(parameter:IntParameter("Segments", 1, .inputfield, "Number of segments for the rounded corners"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputSize", port: self.inputSize),
            PortDeclaration(key: "inputRadius", port: self.inputRadius),
            PortDeclaration(key: "inputResolution", port: self.inputResolution),
        ] + super.declaredPorts()
    }

    public override var geometry: RoundedBoxGeometry { _geometry }

    private lazy var _geometry = RoundedBoxGeometry(context:self.context, size: .init(repeating: 2.0), radius: 0.25, resolution: 3)
    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
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
