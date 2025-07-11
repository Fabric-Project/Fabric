//
//  StandardMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/29/25.
//

import Foundation
import Satin
import simd
import Metal

public class StandardMaterialNode : BaseMaterialNode
{
    public override class var name:String {  "Standard Material" }

    // Params
    public let inputBaseColor: Float4Parameter
    public let inputEmissiveColor: Float4Parameter
    public let inputSpecular: FloatParameter
    public let inputRoughness: FloatParameter
    public let inputMetallic: FloatParameter
    public let inputOcclusion: FloatParameter
    public let inputEnvironmentIntensity: FloatParameter
    public let inputGammaCorrection: FloatParameter

    public override var inputParameters: [any Parameter] { super.inputParameters + [inputBaseColor,
                                                                             inputEmissiveColor,
                                                                             inputSpecular,
                                                                             inputMetallic,
                                                                             inputRoughness,
                                                                             inputOcclusion,
                                                                             inputEnvironmentIntensity,
                                                                             inputGammaCorrection,
                                                                             
    ] }

    // Ports
    public let inputDiffuseTexture: NodePort<EquatableTexture>
    public let inputNormalTexture: NodePort<EquatableTexture>
    public let inputEmissiveTexture: NodePort<EquatableTexture>
    public let inputSpecularTexture: NodePort<EquatableTexture>
    public let inputRoughnessTexture: NodePort<EquatableTexture>
    public let inputMetalicTexture: NodePort<EquatableTexture>

    
    public override var ports: [any NodePortProtocol] {  super.ports + [
        inputDiffuseTexture,
        inputNormalTexture,
        inputEmissiveTexture,
        inputSpecularTexture,
        inputRoughnessTexture,
        inputMetalicTexture,
//        inputBumpTexture,
//        inputOcclusionTexture,
        ] }
    
    public override var material: StandardMaterial {
        return _material
    }
    
    private var _material = StandardMaterial()
    
    public required init(context: Context)
    {
        self.inputBaseColor = Float4Parameter("Base Color", simd_float4(repeating:1), .colorpicker)
        self.inputEmissiveColor = Float4Parameter("Emissive Color", simd_float4(repeating:0), .colorpicker)
        self.inputSpecular = FloatParameter("Specular", 0.25, 0.0, 1.0, .slider)
        self.inputRoughness = FloatParameter("Roughness", 0.25, 0.0, 1.0, .slider)
        self.inputMetallic = FloatParameter("Metallic", 0.75, 0.0, 1.0, .slider)
        self.inputOcclusion = FloatParameter("Occlusion", 0.75, 0.0, 1.0, .slider)
        self.inputEnvironmentIntensity = FloatParameter("Environment Intensity", 1.0, 0.0, 1.0, .slider)
        self.inputGammaCorrection = FloatParameter("Gamma Correction", 1.0, 0.0, 2.4, .slider)

        // Ports
        self.inputDiffuseTexture = NodePort<EquatableTexture>(name: "Diffuse Texture", kind: .Inlet)
        self.inputNormalTexture = NodePort<EquatableTexture>(name: "Normal Texture", kind: .Inlet)
        self.inputEmissiveTexture = NodePort<EquatableTexture>(name: "Emissive Texture", kind: .Inlet)
        self.inputSpecularTexture = NodePort<EquatableTexture>(name: "Specular Texture", kind: .Inlet)
        self.inputRoughnessTexture = NodePort<EquatableTexture>(name: "Roughness Texture", kind: .Inlet)
        self.inputMetalicTexture = NodePort<EquatableTexture>(name: "Metallic Texture", kind: .Inlet)
//        self.inputBumpTexture = NodePort<EquatableTexture>(name: "Bump Texture", kind: .Inlet)
//        self.inputOcclusionTexture = NodePort<EquatableTexture>(name: "Occlusion Texture", kind: .Inlet)
        
        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputBaseColorParameter
        case inputEmissiveColorParameter
        case inputSpecularParameter
        case inputRoughnessParameter
        case inputMetallicParameter
        case inputOcclusionParameter
        case inputEnvironmentIntensityParameter
        case inputGammaCorrectionParameter

        case inputDiffuseTexturePort
        case inputNormalTexturePort
        case inputEmissiveTexturePort
        case inputSpecularTexturePort
        case inputRoughnessTexturePort
        case inputMetalicTexturePort
//        case inputBumpTexturePort
//        case inputOcclusionTexturePort
        
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputBaseColor, forKey: .inputBaseColorParameter)
        try container.encode(self.inputEmissiveColor, forKey: .inputEmissiveColorParameter)
        try container.encode(self.inputSpecular, forKey: .inputSpecularParameter)
        try container.encode(self.inputRoughness, forKey: .inputRoughnessParameter)
        try container.encode(self.inputMetallic, forKey: .inputMetallicParameter)
        try container.encode(self.inputOcclusion, forKey: .inputOcclusionParameter)
        try container.encode(self.inputEnvironmentIntensity, forKey: .inputEnvironmentIntensityParameter)
        try container.encode(self.inputGammaCorrection, forKey: .inputGammaCorrectionParameter)

        try container.encode(self.inputDiffuseTexture, forKey: .inputDiffuseTexturePort)
        try container.encode(self.inputNormalTexture, forKey: .inputNormalTexturePort)
        try container.encode(self.inputEmissiveTexture, forKey: .inputEmissiveTexturePort)
        try container.encode(self.inputSpecularTexture, forKey: .inputSpecularTexturePort)
        try container.encode(self.inputRoughnessTexture, forKey: .inputRoughnessTexturePort)
        try container.encode(self.inputMetalicTexture, forKey: .inputMetalicTexturePort)
//        try container.encode(self.inputBumpTexture, forKey: .inputBumpTexturePort)
//        try container.encode(self.inputOcclusionTexture, forKey: .inputOcclusionTexturePort)

        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)


        self.inputBaseColor = try container.decode(Float4Parameter.self, forKey: .inputBaseColorParameter)
        self.inputEmissiveColor = try container.decode(Float4Parameter.self, forKey: .inputEmissiveColorParameter)
        self.inputSpecular = try container.decode(FloatParameter.self, forKey: .inputSpecularParameter)
        self.inputRoughness = try container.decode(FloatParameter.self, forKey: .inputRoughnessParameter)
        self.inputMetallic = try container.decode(FloatParameter.self, forKey: .inputMetallicParameter)
        self.inputOcclusion = try container.decode(FloatParameter.self, forKey: .inputOcclusionParameter)
        self.inputEnvironmentIntensity = try container.decode(FloatParameter.self, forKey: .inputEnvironmentIntensityParameter)
        self.inputGammaCorrection = try container.decode(FloatParameter.self, forKey: .inputGammaCorrectionParameter)

        self.inputDiffuseTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputDiffuseTexturePort)
        self.inputNormalTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputNormalTexturePort)
        self.inputEmissiveTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputEmissiveTexturePort)
        self.inputSpecularTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputSpecularTexturePort)
        self.inputRoughnessTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputRoughnessTexturePort)
        self.inputMetalicTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputMetalicTexturePort)
//        self.inputBumpTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputBumpTexturePort)
//        self.inputOcclusionTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputOcclusionTexturePort)

        
        try super.init(from: decoder)
    }
    
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        
        self.evaluate(material: self.material, atTime: context.timing.time)

        self.material.baseColor = self.inputBaseColor.value
        self.material.emissiveColor = self.inputEmissiveColor.value
        
        self.material.specular = self.inputSpecular.value
        self.material.metallic = self.inputMetallic.value
        self.material.roughness = self.inputRoughness.value
        self.material.occlusion = self.inputOcclusion.value
        self.material.environmentIntensity = self.inputEnvironmentIntensity.value
        self.material.gammaCorrection = self.inputGammaCorrection.value

        self.material.setTexture(self.inputDiffuseTexture.value?.texture, type: .baseColor)
        self.material.setTexture(self.inputNormalTexture.value?.texture, type: .normal)
        self.material.setTexture(self.inputEmissiveTexture.value?.texture, type: .emissive)
        self.material.setTexture(self.inputSpecularTexture.value?.texture, type: .specular)
        self.material.setTexture(self.inputRoughnessTexture.value?.texture, type: .roughness)
        self.material.setTexture(self.inputMetalicTexture.value?.texture, type: .metallic)
        
//        self.material.setTexture(self.inputBumpTexture.value?.texture, type: .displacement)
//        self.material.setTexture(self.inputOcclusionTexture.value?.texture, type: .occlusion)
                
        
        self.outputMaterial.send(self.material)
     }
}
