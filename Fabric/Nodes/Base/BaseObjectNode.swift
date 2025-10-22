
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
            ("inputRenderOrder", ParameterPort(parameter:IntParameter("Render Order", 0) ) ),
            ("inputRenderPass", ParameterPort(parameter:IntParameter("Render Pass", 0) ) ),

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

    
    
    
    // Params
//    public var inputVisible:BoolParameter = BoolParameter("Visible", true)
//    public var inputRenderOrder:IntParameter = IntParameter("Render Order", 0)
//    public var inputRenderPass:IntParameter = IntParameter("Render Pass", 0)
//    
//    public var inputPosition:Float3Parameter
//    public var inputScale:Float3Parameter
//    public var inputOrientation:Float4Parameter
//
//    public override var inputParameters: [any Parameter] { [
//        self.inputVisible,
//        self.inputRenderOrder,
//        self.inputRenderPass,
//        self.inputPosition,
//        self.inputScale,
//        self.inputOrientation] + super.inputParameters}
    
    override public func getObject() -> Object? {
        return self.object
    }
    
    var object: ObjectType? {
        return nil
    }

//    public required init(context: Context)
//    {
//        self.inputVisible = BoolParameter("Visible", true)
//        self.inputRenderOrder = IntParameter("Render Order", 0)
//        self.inputRenderPass = IntParameter("Render Pass", 0)
//        
//        self.inputPosition = Float3Parameter("Position", simd_float3(repeating:0), .inputfield )
//        self.inputScale =  Float3Parameter("Scale", simd_float3(repeating:1), .inputfield)
//        self.inputOrientation = Float4Parameter("Orientation", simd_float4(x: 0, y: 1, z: 0, w: 0) , .inputfield)
//        
//        super.init(context: context)
//    }
//        
//    enum CodingKeys : String, CodingKey
//    {
//        case inputVisibleParameter
//        case inputRenderOrderParameter
//        case inputRenderPassParameter
//        case inputPositionParameter
//        case inputScaleParameter
//        case inputOrientationParameter
//    }
//    
//    public override func encode(to encoder:Encoder) throws
//    {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        
//        try container.encode(self.inputVisible, forKey: .inputVisibleParameter)
//        try container.encode(self.inputRenderOrder, forKey: .inputRenderOrderParameter)
//        try container.encode(self.inputRenderPass, forKey: .inputRenderPassParameter)
//
//        try container.encode(self.inputPosition, forKey: .inputPositionParameter)
//        try container.encode(self.inputScale, forKey: .inputScaleParameter)
//        try container.encode(self.inputOrientation, forKey: .inputOrientationParameter)
//
//        try super.encode(to: encoder)
//    }
//    
//    public required init(from decoder: any Decoder) throws
//    {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//
//        self.inputPosition = try container.decode(Float3Parameter.self, forKey: .inputPositionParameter)
//        self.inputScale = try container.decode(Float3Parameter.self, forKey: .inputScaleParameter)
//        self.inputOrientation = try container.decode(Float4Parameter.self, forKey: .inputOrientationParameter)
//
//        self.inputVisible = try container.decodeIfPresent(BoolParameter.self, forKey: .inputVisibleParameter) ??  BoolParameter("Visible", true)
//        self.inputRenderOrder = try container.decodeIfPresent(IntParameter.self, forKey: .inputRenderOrderParameter) ?? IntParameter("Render Order", 0)
//        self.inputRenderPass = try container.decodeIfPresent(IntParameter.self, forKey: .inputRenderPassParameter) ?? IntParameter("Render Pass", 0)
//
//        try super.init(from: decoder)
//        
//    }

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
            object.orientation = simd_quatf(angle: orientation.w,
                                            axis: simd_float3(x: orientation.x,
                                                              y: orientation.y,
                                                              z: orientation.z) )
            shouldOutput = true
        }
        
        if self.isDirty
        {
            shouldOutput = true
        }
        
        return shouldOutput
    }
}
