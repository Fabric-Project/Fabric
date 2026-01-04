
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


public class BaseRenderableNode<ObjectType : Renderable> : ObjectNode<ObjectType>
{
    
    override public func evaluate(object:Object?, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(object: object, atTime: atTime)

        guard let renderable = object as? Renderable else { return shouldOutput }

        if self.inputRenderOrder.valueDidChange
        {
            renderable.renderOrder = self.inputRenderOrder.value ?? 0
            shouldOutput = true
        }
        
        if self.inputRenderPass.valueDidChange
        {
            renderable.renderPass = self.inputRenderPass.value ?? 0
            shouldOutput = true
        }
        
        return shouldOutput
    }
    
    
}
