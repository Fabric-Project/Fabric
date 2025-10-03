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

public class IcoSphereGeometryNode : BaseGeometryNode
{
    public override class var name:String { "IcoSphere Geometry" }

    // Params
    public let inputRadius:FloatParameter
    public let inputResolutionParam:IntParameter
    override public var inputParameters: [any Parameter] { [inputRadius, inputResolutionParam] + super.inputParameters}

    public override var geometry: IcoSphereGeometry { _geometry }
    private let _geometry = IcoSphereGeometry(radius: 1.0, resolution: 1)

    required public init(context: Context)
    {
        self.inputRadius = FloatParameter("Radius", 1.0, .inputfield)
        self.inputResolutionParam = IntParameter("Resolution", 1, .inputfield)


        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputRadiusParameter
        case inputResolutionParameter
    }
    
    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputRadius, forKey: .inputRadiusParameter)
        try container.encode(self.inputResolutionParam, forKey: .inputResolutionParameter)
        
        try super.encode(to: encoder)
    }
    
    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputRadius = try container.decode(FloatParameter.self, forKey: .inputRadiusParameter)
        self.inputResolutionParam = try container.decode(IntParameter.self, forKey: .inputResolutionParameter)
        
        try super.init(from: decoder)
    }
    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputRadius.valueDidChange
        {
            self.geometry.radius = self.inputRadius.value
            shouldOutputGeometry = true
        }
                
        if  self.inputResolutionParam.valueDidChange
        {
            self.geometry.resolution =  self.inputResolutionParam.value
            shouldOutputGeometry = true
        }
       
        return shouldOutputGeometry
     }
}
