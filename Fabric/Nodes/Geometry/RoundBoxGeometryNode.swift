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

    // Params
    public let inputWidthParam:FloatParameter
    public let inputHeightParam:FloatParameter
    public let inputRadiusParam:FloatParameter
    public let inputResolutionParam:Int2Parameter
    public override var inputParameters: [any Parameter] { [inputWidthParam, inputHeightParam, inputRadiusParam, inputResolutionParam] + super.inputParameters}

    public override var geometry: RoundedBoxGeometry { _geometry }

    private let _geometry = RoundedBoxGeometry(size: .init(repeating: 2.0), radius: 0.25, resolution: 3)

    required public init(context: Context)
    {
        self.inputWidthParam = FloatParameter("Width", 1.0, .inputfield)
        self.inputHeightParam = FloatParameter("Height", 1.0, .inputfield)
        self.inputRadiusParam = FloatParameter("Radius", 0.2, .inputfield)
        self.inputResolutionParam = Int2Parameter("Resolution", simd_int2(repeating: 32), .inputfield)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputWidthParameter
        case inputHeightParameter
        case inputRadiusParameter
        case inputResolutionParameter
    }
    
    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputWidthParam, forKey: .inputWidthParameter)
        try container.encode(self.inputHeightParam, forKey: .inputHeightParameter)
        try container.encode(self.inputRadiusParam, forKey: .inputRadiusParameter)
        try container.encode(self.inputResolutionParam, forKey: .inputResolutionParameter)
        
        try super.encode(to: encoder)
    }
    
    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputWidthParam = try container.decode(FloatParameter.self, forKey: .inputWidthParameter)
        self.inputHeightParam = try container.decode(FloatParameter.self, forKey: .inputHeightParameter)
        self.inputRadiusParam = try container.decode(FloatParameter.self, forKey: .inputRadiusParameter)
        self.inputResolutionParam = try container.decode(Int2Parameter.self, forKey: .inputResolutionParameter)
        
        try super.init(from: decoder)
    }
    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

//        if self.inputWidthParam.valueDidChange || self.inputHeightParam.valueDidChange
//        {
//            self.geometry.size = simd_float2( self.inputWidthParam.value, self.inputHeightParam.value)
//            shouldOutputGeometry = true
//        }
//        
//        if self.inputRadiusParam.valueDidChange
//        {
//            self.geometry.radius = max(0.0001, self.inputRadiusParam.value)
//            shouldOutputGeometry = true
//        }
//        
//        if  self.inputResolutionParam.valueDidChange
//        {
//            self.geometry.angularResolution = Int(self.inputResolutionParam.value.x)
//            self.geometry.radialResolution = Int(self.inputResolutionParam.value.y)
//            shouldOutputGeometry = true
//        }
        
        return shouldOutputGeometry
     }
}
