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

public class DirectionalLightNode : ObjectNode<DirectionalLight>
{
    public override class var name:String { "Directional Light" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Object(objectType: .Light) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Adds a Directional Light to the scene."}

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
            ("inputLookAt", ParameterPort(parameter:Float3Parameter("Look At", simd_float3(repeating:0), .inputfield, "Target position the light points toward")) ),
            ("inputColor", ParameterPort(parameter:Float3Parameter("Color", simd_float3(repeating:1), .inputfield, "RGB color of the light")) ),

            ("inputIntensity", ParameterPort(parameter: FloatParameter("Intensity", 1.0, 0.0, 10.0, .slider, "Brightness multiplier for the light"))),
            ("inputShadowStrength", ParameterPort(parameter: FloatParameter("Shadow Strength", 0.5, 0.0, 1.0, .slider, "Opacity of cast shadows (0 = invisible, 1 = fully dark)"))),
            ("inputShadowRadius", ParameterPort(parameter: FloatParameter("Shadow Radius", 2.0, 0.0, 16.0, .slider, "Blur radius for soft shadow edges"))),
            ("inputShadowBias", ParameterPort(parameter: FloatParameter("Shadow Bias", 0.005, 0.0, 1.0, .slider, "Offset to prevent shadow acne artifacts"))),
        ] + ports
    }
    
    // Proxy Port
    public var inputLookAt:ParameterPort<simd_float3> { port(named: "inputLookAt") }
    public var inputColor: ParameterPort<simd_float3> { port(named: "inputColor") }
    public var inputIntensity: ParameterPort<Float> { port(named: "inputIntensity") }
    public var inputShadowStrength: ParameterPort<Float> { port(named: "inputShadowStrength") }
    public var inputShadowRadius: ParameterPort<Float> { port(named: "inputShadowRadius") }
    public var inputShadowBias: ParameterPort<Float> { port(named: "inputShadowBias") }
    
    public override var object: DirectionalLight? {
        return light
    }
    
    private var light: DirectionalLight =  DirectionalLight(color: [1.0, 1.0, 1.0], intensity: 1.0)
  
    override public func startExecution(context:GraphExecutionContext)
    {
        self.setupDefaultLight( )
    }
    
    private func setupDefaultLight()
    {
        self.light.context = self.context
        self.light.lookAt(target: .zero, up: Satin.worldUpDirection)

        self.light.castShadow = true
        self.light.shadow.resolution = (2048, 2048)
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
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let _ = self.evaluate(object: self.light, atTime: context.timing.time)
    }
}
