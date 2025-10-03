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

public class BoxGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Box Geometry" }

    // Params
    public let inputWidthParam:FloatParameter
    public let inputHeightParam:FloatParameter
    public let inputDepthParam:FloatParameter
    public let inputResolutionParam:Int3Parameter
    public override var inputParameters: [any Parameter] { [inputWidthParam, inputHeightParam, inputDepthParam, inputResolutionParam] + super.inputParameters }

    public override var geometry: BoxGeometry { _geometry }
    
    private let _geometry = BoxGeometry(width: 1, height: 1, depth: 1)

    required public init(context: Context)
    {
        self.inputWidthParam = FloatParameter("Width", 1.0, .inputfield)
        self.inputHeightParam = FloatParameter("Height", 1.0, .inputfield)
        self.inputDepthParam = FloatParameter("Depth", 1.0, .inputfield)
        self.inputResolutionParam = Int3Parameter("Resolution", simd_int3(repeating: 1), .inputfield)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputWidthParameter
        case inputHeightParameter
        case inputDepthParameter
        case inputResolutionParameter
    }
    
    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputWidthParam, forKey: .inputWidthParameter)
        try container.encode(self.inputHeightParam, forKey: .inputHeightParameter)
        try container.encode(self.inputDepthParam, forKey: .inputDepthParameter)
        try container.encode(self.inputResolutionParam, forKey: .inputResolutionParameter)
        
        try super.encode(to: encoder)
    }
    
    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputWidthParam = try container.decode(FloatParameter.self, forKey: .inputWidthParameter)
        self.inputHeightParam = try container.decode(FloatParameter.self, forKey: .inputHeightParameter)
        self.inputDepthParam = try container.decode(FloatParameter.self, forKey: .inputDepthParameter)
        self.inputResolutionParam = try container.decode(Int3Parameter.self, forKey: .inputResolutionParameter)
        
        try super.init(from: decoder)
    }
    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)
        
        if self.inputWidthParam.valueDidChange
        {
            self.geometry.width = self.inputWidthParam.value
            shouldOutputGeometry = true
        }
        
        if self.inputHeightParam.valueDidChange
        {
            self.geometry.height = self.inputHeightParam.value
            shouldOutputGeometry = true
        }
        
        if self.inputDepthParam.valueDidChange
        {
            self.geometry.depth = self.inputDepthParam.value
            shouldOutputGeometry = true
        }
        
        if self.inputResolutionParam.valueDidChange
        {
            self.geometry.resolution =  self.inputResolutionParam.value
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
    }
}
