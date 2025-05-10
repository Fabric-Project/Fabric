
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

class BaseObjectNode : Node
{
    public var inputPosition = Float3Parameter("Position", simd_float3(repeating:0), .inputfield )
    public var inputScale = Float3Parameter("Scale", simd_float3(repeating:1), .inputfield)
    public var inputOrientation = Float4Parameter("Orientation", simd_float4(x: 0, y: 1, z: 0, w: 0) , .inputfield)

    override var inputParameters: [any Parameter] { super.inputParameters + [self.inputPosition, self.inputScale, self.inputOrientation] }
    

    public func evaluate(object:Object, atTime:TimeInterval)
    {
        object.scale = self.inputScale.value
        object.position = self.inputPosition.value
        object.orientation = simd_quatf(vector:  self.inputOrientation.value )
    }
}
