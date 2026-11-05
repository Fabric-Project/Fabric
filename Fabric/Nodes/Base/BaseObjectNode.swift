
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

open class BaseObjectNode : Node
{
    override open class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override open class var nodeTimeMode: Node.TimeMode { .None }

    open func getObject() -> Object? {
        return nil
    }
}


open class ObjectNode<ObjectType : Satin.Object> : BaseObjectNode
{
    public let inputVisible = ParameterPort(parameter:BoolParameter("Visible", true, .button, "When enabled, the object is rendered in the scene") )
    public let inputRenderOrder = ParameterPort(parameter:IntParameter("Render Order", 0, .inputfield, "Draw order within the same render pass (lower = earlier)") )
    public let inputPosition: ParameterPort<simd_float3>
    public let inputScale: ParameterPort<simd_float3>
    public let inputOrientation: ParameterPort<simd_float4>

    /// The position, scale and orientation inlets, made per class so a
    /// subclass can give them its own defaults and wording under the same keys.
    open class func makePlacementPorts() -> (position: ParameterPort<simd_float3>, scale: ParameterPort<simd_float3>, orientation: ParameterPort<simd_float4>)
    {
        (
            position: ParameterPort(parameter:Float3Parameter("Position", simd_float3(repeating:0), .inputfield, "Position in 3D space (X, Y, Z) in world units") ),
            scale: ParameterPort(parameter:Float3Parameter("Scale", simd_float3(repeating:1), .inputfield, "Scale factor along each axis (X, Y, Z)") ),
            orientation: ParameterPort(parameter:Float4Parameter("Orientation", simd_float4(repeating:0), .inputfield, "Orientation as quaternion (X, Y, Z, W)") )
        )
    }

    public required init(context: Context)
    {
        (self.inputPosition, self.inputScale, self.inputOrientation) = Self.makePlacementPorts()
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        (self.inputPosition, self.inputScale, self.inputOrientation) = Self.makePlacementPorts()
        try super.init(from: decoder)
    }

    override open func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputVisible", port: self.inputVisible),
            PortDeclaration(key: "inputRenderOrder", port: self.inputRenderOrder),
            PortDeclaration(key: "inputPosition", port: self.inputPosition),
            PortDeclaration(key: "inputScale", port: self.inputScale),
            PortDeclaration(key: "inputOrientation", port: self.inputOrientation),
        ] + super.declaredPorts()
    }

    override open func getObject() -> Object? {
        return self.object
    }

    open var object: ObjectType? {
        return nil
    }

    open func evaluate(object:Object?, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = false
        
        guard let object else { return shouldOutput }
        
        if self.inputVisible.valueDidChange
        {
            object.visible = self.inputVisible.value ?? true
            shouldOutput = true
        }
       
        
        if self.inputScale.valueDidChange,
           let scale = self.inputScale.value
        {
            object.scale = scale
            shouldOutput = true
        }
        
        if self.inputPosition.valueDidChange,
           let position = self.inputPosition.value
        {
            object.position = position
            shouldOutput = true
        }
        
        if  self.inputOrientation.valueDidChange,
            let orientation = self.inputOrientation.value
        {
            object.orientation = simd_quatf(vector:orientation).normalized
            shouldOutput = true
        }
        
        // We use this for disconnect / reconnect logic...
        // Maybe this needs to go into a super call? :X
        if self.isDirty
        {
            shouldOutput = true
        }
        
        return shouldOutput
    }
}
