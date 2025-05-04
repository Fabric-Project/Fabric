
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
    public var inputPosition = GenericParameter<simd_float3>("Position", simd_float3(repeating:0) )
    public var inputScale = GenericParameter<simd_float3>("Scale", simd_float3(repeating:1) )
    public var inputOrientation = GenericParameter<simd_quatf>("Orientation", simd_quatf(angle: 0, axis: Satin.worldUpDirection) )

    override var inputParameters: [any Parameter] { super.inputParameters + [self.inputPosition, self.inputScale, self.inputOrientation] }
    

    public func evaluate(object:Object, atTime:TimeInterval)
    {
        object.scale = self.inputScale.value
        object.position = self.inputPosition.value
        object.orientation = self.inputOrientation.value
    }
}
