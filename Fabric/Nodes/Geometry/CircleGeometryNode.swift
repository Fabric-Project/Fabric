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

    // Params
    public let inputSizeParam:FloatParameter
    public override var inputParameters: [any Parameter] { [inputSizeParam] + super.inputParameters}

    public override var geometry: CircleGeometry { _geometry }

    
    private let _geometry = CircleGeometry(radius: 1.0, angularResolution: 60, radialResolution: 1)
    required public init(context: Context)
    {
        self.inputSizeParam = FloatParameter("Size", 1.0, .inputfield)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputSizeParameter
    }
    
    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputSizeParam, forKey: .inputSizeParameter)
        
        try super.encode(to: encoder)
    }
    
    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputSizeParam = try container.decode(FloatParameter.self, forKey: .inputSizeParameter)
        
        try super.init(from: decoder)
    }
    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputSizeParam.valueDidChange
        {
            self._geometry.radius = self.inputSizeParam.value
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}
