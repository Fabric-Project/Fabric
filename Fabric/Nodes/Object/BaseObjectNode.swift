
//
//  BaseObjectNodr.swift
//  Fabric
//
//  Created by Anton Marini on 5/4/25.
//

import Foundation
import Satin
import simd
import Metal

public class BaseObjectNode : Node
{
    // Params
    public var inputPosition:Float3Parameter
    public var inputScale:Float3Parameter
    public var inputOrientation:Float4Parameter

    public override var inputParameters: [any Parameter] { [self.inputPosition, self.inputScale, self.inputOrientation] + super.inputParameters}
    
    public required init(context: Context)
    {
        self.inputPosition = Float3Parameter("Position", simd_float3(repeating:0), .inputfield )
        self.inputScale =  Float3Parameter("Scale", simd_float3(repeating:1), .inputfield)
        self.inputOrientation = Float4Parameter("Orientation", simd_float4(x: 0, y: 1, z: 0, w: 0) , .inputfield)
        
        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputPositionParameter
        case inputScaleParameter
        case inputOrientationParameter
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputPosition, forKey: .inputPositionParameter)
        try container.encode(self.inputScale, forKey: .inputScaleParameter)
        try container.encode(self.inputOrientation, forKey: .inputOrientationParameter)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputPosition = try container.decode(Float3Parameter.self, forKey: .inputPositionParameter)
        self.inputScale = try container.decode(Float3Parameter.self, forKey: .inputScaleParameter)
        self.inputOrientation = try container.decode(Float4Parameter.self, forKey: .inputOrientationParameter)
        
        try super.init(from: decoder)
    }

    public func evaluate(object:Object, atTime:TimeInterval)
    {
        object.scale = self.inputScale.value
        object.position = self.inputPosition.value
        object.orientation = simd_quatf(angle: self.inputOrientation.value.w,
                                        axis: simd_float3(x: self.inputOrientation.value.x, y: self.inputOrientation.value.y, z: self.inputOrientation.value.z) )
    }
}
