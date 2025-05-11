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

class DirectionalLightNode : BaseObjectNode, NodeProtocol
{
    static let name = "Directional Light"
    static var nodeType = Node.NodeType.Light

    // Params
    let inputLookAt: Float3Parameter
    let inputColor: Float3Parameter
    let inputIntensity: FloatParameter
    let inputShadowStrength: FloatParameter
    let inputShadowRadius: FloatParameter
    let inputShadowBias: FloatParameter
    
    override var inputParameters: [any Parameter] { super.inputParameters + [inputLookAt, inputColor, inputIntensity, inputShadowStrength, inputShadowRadius, inputShadowBias] }
    
    // Ports
    let outputLight: NodePort<Object>
    override var ports: [any NodePortProtocol] { super.ports +  [outputLight] }
    
    private var light: DirectionalLight =  DirectionalLight(color: [1.0, 1.0, 1.0], intensity: 1.0)

//    let lightHelperGeo = BoxGeometry(width: 0.1, height: 0.1, depth: 0.5)
//    let lightHelperMat = BasicDiffuseMaterial(hardness: 0.7)
//    lazy var lightHelperMesh0 = Mesh(geometry: lightHelperGeo, material: lightHelperMat)

    required init(context:Context)
    {
        self.inputLookAt = Float3Parameter("Look At", simd_float3(repeating:0), .inputfield )
        self.inputColor = Float3Parameter("Color", simd_float3(repeating:1), .inputfield )
        self.inputIntensity = FloatParameter("Intensity", 1.0, 0.0, 10.0, .slider)
        self.inputShadowStrength = FloatParameter("Shadow Strength", 0.5, 0.0, 1.0, .slider)
        self.inputShadowRadius = FloatParameter("Shadow Radius", 2.0, 0.0, 10.0, .slider)
        self.inputShadowBias = FloatParameter("Shadow Bias", 0.005, 0.0, 1.0, .slider)
        
        self.outputLight = NodePort<Object>(name: MeshNode.name, kind: .Outlet)
        
        super.init(context: context)
        
        light.castShadow = true
        light.shadow.resolution = (1024, 1024)
        light.shadow.bias = 0.0005
        light.shadow.strength = 0.5
        light.shadow.radius = 2
        light.position.y = 5.0
        
        // Not sure what this does TBH :X ?
//        if let shadowCamera = light.shadow.camera as? OrthographicCamera {
//            shadowCamera.update(left: -2, right: 2, bottom: -2, top: 2)
//        }

        light.lookAt(target: .zero, up: Satin.worldUpDirection)

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
    
    override func encode(to encoder:Encoder) throws
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

    required init(from decoder: any Decoder) throws
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
    }

    override func evaluate(atTime:TimeInterval,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        self.light.color = self.inputColor.value
        self.light.intensity = self.inputIntensity.value
        self.light.shadow.strength = self.inputShadowStrength.value
        self.light.shadow.radius = self.inputShadowRadius.value
        self.light.shadow.bias = self.inputShadowBias.value

        self.evaluate(object: self.light, atTime: atTime)
        
        self.light.lookAt(target: self.inputLookAt.value)
        
        self.outputLight.send(light)
    }
}
