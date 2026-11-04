//
//  DirectionalLightNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//


import Foundation
import Satin
import simd
import Metal

public class PointLightNode : ObjectNode<PointLight>
{
    public override class var name:String { "Point Light" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Object(objectType: .Light) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Adds a Point Light to the scene."}

    public let inputLookAt = ParameterPort(parameter:Float3Parameter("Look At", simd_float3(repeating:0), .inputfield, "Target position the light points toward"))
    public let inputColor = ParameterPort(parameter:Float3Parameter("Color", simd_float3(repeating:1), .inputfield, "RGB color of the light"))
    public let inputIntensity = ParameterPort(parameter: FloatParameter("Intensity", 1.0, 0.0, 10.0, .slider, "Brightness multiplier for the light"))
    public let inputRadius = ParameterPort(parameter: FloatParameter("Radius", 1.0, 0.0, 1000.0, .slider, "Distance at which the light falls off to zero"))
    public let inputShadowStrength = ParameterPort(parameter: FloatParameter("Shadow Strength", 0.5, 0.0, 1.0, .slider, "Opacity of cast shadows (0 = invisible, 1 = fully dark)"))
    public let inputShadowRadius = ParameterPort(parameter: FloatParameter("Shadow Radius", 2.0, 0.0, 10.0, .slider, "Blur radius for soft shadow edges"))
    public let inputShadowBias = ParameterPort(parameter: FloatParameter("Shadow Bias", 0.005, 0.0, 1.0, .slider, "Offset to prevent shadow acne artifacts"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputLookAt", port: self.inputLookAt),
            PortDeclaration(key: "inputColor", port: self.inputColor),
            PortDeclaration(key: "inputIntensity", port: self.inputIntensity),
            PortDeclaration(key: "inputRadius", port: self.inputRadius),
            PortDeclaration(key: "inputShadowStrength", port: self.inputShadowStrength),
            PortDeclaration(key: "inputShadowRadius", port: self.inputShadowRadius),
            PortDeclaration(key: "inputShadowBias", port: self.inputShadowBias),
        ] + super.declaredPorts()
    }

    public override var object: PointLight? {
        return light
    }
    
    private lazy var light: PointLight =  PointLight(context:self.context, color: simd_float3(1.0, 1.0, 1.0), radius: 150.0)

    override public func startExecution(renderer:GraphRenderer)
    throws
    {
        self.setupDefaultLight( )
        try super.startExecution(renderer: renderer)
    }
    
    private func setupDefaultLight()
    {
        self.light.lookAt(target: .zero, up: Satin.worldUpDirection)

        self.light.castShadow = true
        self.light.shadow.resolution = (1024, 1024)
        self.light.shadow.bias = 0.0005
        self.light.shadow.strength = 0.5
        self.light.shadow.radius = 2
        
        // So this is 'sus' - i think for large shadow volumes we needed to adjust the ortho camera,
        // But for smaller simpler scenes, the following is wrong.
        // Not sure how to tune?
//        if let shadowCamera = self.light.shadow.camera as? OrthographicCamera {
//            shadowCamera.update(left: -20, right: 20, bottom: -20, top: 20, near: 0.01, far: 200)
//        }
    }
    
    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(object: object, atTime: atTime)
        
        if self.inputColor.valueDidChange,
           let color = self.inputColor.value
        {
            self.light.color = color
            shouldOutput = true
        }
        
        if self.inputIntensity.valueDidChange,
           let intensity = self.inputIntensity.value
        {
            self.light.intensity = intensity
            shouldOutput = true
        }
        
        if self.inputRadius.valueDidChange,
           let radius = self.inputRadius.value
        {
            self.light.radius = radius
            shouldOutput = true
        }
        
        if self.inputShadowStrength.valueDidChange,
           let inputShadowStrength =  self.inputShadowStrength.value
        {
            self.light.shadow.strength = inputShadowStrength
            shouldOutput = true
        }
        
        if self.inputShadowRadius.valueDidChange,
           let inputShadowRadius = self.inputShadowRadius.value
        {
            self.light.shadow.radius = inputShadowRadius
            shouldOutput = true
        }
        
        if self.inputShadowBias.valueDidChange,
           let inputShadowBias = self.inputShadowBias.value
        {
            self.light.shadow.bias = inputShadowBias
            shouldOutput = true
        }
        
        // Needs to fire every frame
        self.light.lookAt(target: self.inputLookAt.value ?? .zero)
        
        return shouldOutput
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let _ = self.evaluate(object: self.light, atTime: executionInfo.timing.time)
    }
}
