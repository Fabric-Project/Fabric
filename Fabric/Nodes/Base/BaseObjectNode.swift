
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
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }

    public func getObject() -> Object? {
        return nil
    }
}


public class ObjectNode<ObjectType : Satin.Object> : BaseObjectNode
{
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return [
            ("inputVisible", ParameterPort(parameter:BoolParameter("Visible", true, .button) ) ),
            ("inputRenderOrder", ParameterPort(parameter:IntParameter("Render Order", 0, .inputfield) ) ),
            ("inputRenderPass", ParameterPort(parameter:IntParameter("Render Pass", 0, .inputfield) ) ),

            ("inputPosition", ParameterPort(parameter:Float3Parameter("Position", simd_float3(repeating:0), .inputfield ) ) ),

            ("inputScale", ParameterPort(parameter:Float3Parameter("Scale", simd_float3(repeating:1), .inputfield ) ) ),

            ("inputOrientation", ParameterPort(parameter:Float4Parameter("Orientation", simd_float4(repeating:0), .inputfield ) ) ),

        ] + ports
    }
    
    // Port Proxy
    public var inputVisible:ParameterPort<Bool>    { port(named: "inputVisible") }
    public var inputRenderOrder:ParameterPort<Int>          { port(named: "inputRenderOrder") }
    public var inputRenderPass:ParameterPort<Int>           { port(named: "inputRenderPass") }
    
    public var inputPosition:ParameterPort<simd_float3>          { port(named: "inputPosition") }
    public var inputScale:ParameterPort<simd_float3>          { port(named: "inputScale") }
    public var inputOrientation:ParameterPort<simd_float4>          { port(named: "inputOrientation") }
    
    override public func getObject() -> Object? {
        return self.object
    }
    
    var object: ObjectType? {
        return nil
    }

    public func evaluate(object:Object?, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = false
        
        guard let object else { return shouldOutput }
        
//        if self.inputVisible.valueDidChange
//        {
//            object.visible = self.inputVisible.value
//            shouldOutput = true
//        }
//        
//        if self.inputRenderPass.valueDidChange
//        {
//            object.renderPass = self.inputRenderPass.value
//            shouldOutput = true
//        }
//        
//        if self.inputRenderPass.valueDidChange
//        {
//            object.renderPass = self.inputRenderPass.value
//            shouldOutput = true
//        }
        
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
