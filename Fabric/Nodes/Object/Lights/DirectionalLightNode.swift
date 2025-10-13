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

public class DirectionalLightNode : BaseObjectNode, ObjectNodeProtocol
{
    public override var name:String { "Directional Light" }
    public override var nodeType:Node.NodeType { Node.NodeType.Object(objectType: .Light) }

    // Params
    public let inputLookAt: Float3Parameter
    public let inputColor: Float3Parameter
    public let inputIntensity: FloatParameter
    public let inputShadowStrength: FloatParameter
    public let inputShadowRadius: FloatParameter
    public let inputShadowBias: FloatParameter
    
    public override var inputParameters: [any Parameter] {  [
        inputLookAt,
        inputColor,
        inputIntensity,
        inputShadowStrength,
        inputShadowRadius,
        inputShadowBias] + super.inputParameters }
    
    // Ports
    public let outputLight: NodePort<Object>
    public override var ports: [any NodePortProtocol] {  [outputLight] + super.ports }
    
    public var object: Object? {
        return light
    }
    
    private var light: DirectionalLight =  DirectionalLight(color: [1.0, 1.0, 1.0], intensity: 1.0)

//    let lightHelperGeo = BoxGeometry(width: 0.1, height: 0.1, depth: 0.5)
//    let lightHelperMat = BasicDiffuseMaterial(hardness: 0.7)
//    lazy var lightHelperMesh0 = Mesh(geometry: lightHelperGeo, material: lightHelperMat)

    public required init(context:Context)
    {
        self.inputLookAt = Float3Parameter("Look At", simd_float3(repeating:0), .inputfield )
        self.inputColor = Float3Parameter("Color", simd_float3(repeating:1), .inputfield )
        self.inputIntensity = FloatParameter("Intensity", 1.0, 0.0, 1000.0, .slider)
        self.inputShadowStrength = FloatParameter("Shadow Strength", 0.5, 0.0, 1.0, .slider)
        self.inputShadowRadius = FloatParameter("Shadow Radius", 2.0, 0.0, 10.0, .slider)
        self.inputShadowBias = FloatParameter("Shadow Bias", 0.005, 0.0, 1.0, .slider)
        
        self.outputLight = NodePort<Object>(name: MeshNode.name, kind: .Outlet)
        
        super.init(context: context)
        
        self.setupDefaultLight()
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputLookAtParameter
        case inputColorParameter
        case inputIntensityParameter
        case inputShadowStrengthParameter
        case inputShadowRadiusParameter
        case inputShadowBiasParameter
        
        case outputLightPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputLookAt, forKey: .inputLookAtParameter)
        try container.encode(self.inputColor, forKey: .inputColorParameter)
        try container.encode(self.inputIntensity, forKey: .inputIntensityParameter)
        try container.encode(self.inputShadowStrength, forKey: .inputShadowStrengthParameter)
        try container.encode(self.inputShadowRadius, forKey: .inputShadowRadiusParameter)
        try container.encode(self.inputShadowBias, forKey: .inputShadowBiasParameter)

        try container.encode(self.outputLight, forKey: .outputLightPort)
        
        try super.encode(to: encoder)
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputLookAt = try container.decode(Float3Parameter.self, forKey: .inputLookAtParameter)
        self.inputColor = try container.decode(Float3Parameter.self, forKey: .inputColorParameter)
        self.inputIntensity = try container.decode(FloatParameter.self, forKey: .inputIntensityParameter)
        self.inputShadowStrength = try container.decode(FloatParameter.self, forKey: .inputShadowStrengthParameter)
        self.inputShadowRadius = try container.decode(FloatParameter.self, forKey: .inputShadowRadiusParameter)
        self.inputShadowBias = try container.decode(FloatParameter.self, forKey: .inputShadowBiasParameter)
        self.outputLight = try container.decode(NodePort<Object>.self, forKey: .outputLightPort)

        try super.init(from: decoder)
        
        self.setupDefaultLight()
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

        if let shadowCamera = self.light.shadow.camera as? OrthographicCamera {
            shadowCamera.update(left: -20, right: 20, bottom: -20, top: 20, near: 0.01, far: 200)
        }

    }

    override public func evaluate(object: Object, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(object: object, atTime: atTime)
    
        if self.inputColor.valueDidChange
        {
            self.light.color = self.inputColor.value
            shouldOutput = true
        }
        
        if self.inputIntensity.valueDidChange
        {
            self.light.intensity = self.inputIntensity.value
            shouldOutput = true
        }
        
        if self.inputShadowStrength.valueDidChange
        {
            self.light.shadow.strength = self.inputShadowStrength.value
            shouldOutput = true
        }
        
        if self.inputShadowRadius.valueDidChange
        {
            self.light.shadow.radius = self.inputShadowRadius.value
            shouldOutput = true
        }
        
        if self.inputShadowBias.valueDidChange
        {
            self.light.shadow.bias = self.inputShadowBias.value
            shouldOutput = true
        }
        
        // Needs to fire every frame
        self.light.lookAt(target: self.inputLookAt.value)
        
        return shouldOutput
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let shouldUpdate = self.evaluate(object: self.light, atTime: context.timing.time)

        if shouldUpdate
        {
            self.outputLight.send(light)
        }
    }
}
