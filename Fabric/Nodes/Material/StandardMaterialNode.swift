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

class StandardMaterialNode : BaseMaterialNode, NodeProtocol
{
    static let name = "Standard Material"
    static var nodeType = Node.NodeType.Material

    // Params
    let inputBaseColor: Float4Parameter
    let inputEmissiveColor: Float4Parameter
    let inputSpecular: FloatParameter
    let inputRoughness: FloatParameter
    let inputMetallic: FloatParameter
    let inputOcclusion: FloatParameter

    override var inputParameters: [any Parameter] { super.inputParameters + [inputBaseColor, inputEmissiveColor, inputSpecular, inputMetallic, inputRoughness, inputOcclusion, ] }

    // Ports
    let inputDiffuseTexture: NodePort<EquatableTexture>
    let inputNormalTexture: NodePort<EquatableTexture>
    let outputMaterial: NodePort<Material>
    
    override var ports: [any NodePortProtocol] {  super.ports + [ inputDiffuseTexture,
                                                         inputNormalTexture,
                                                         outputMaterial] }
    private let material = StandardMaterial()

    
    required init(context: Context)
    {
        self.inputBaseColor = Float4Parameter("Base Color", simd_float4(repeating:1), .colorpicker)
        self.inputEmissiveColor = Float4Parameter("Emissive Color", simd_float4(repeating:0), .colorpicker)
        self.inputSpecular = FloatParameter("Specular", 0.25, 0.0, 1.0, .slider)
        self.inputRoughness = FloatParameter("Roughness", 0.25, 0.0, 1.0, .slider)
        self.inputMetallic = FloatParameter("Metallic", 0.75, 0.0, 1.0, .slider)
        self.inputOcclusion = FloatParameter("Occlusion", 0.75, 0.0, 1.0, .slider)

        // Ports
        self.inputDiffuseTexture = NodePort<EquatableTexture>(name: "Diffuse Texture", kind: .Inlet)
        self.inputNormalTexture = NodePort<EquatableTexture>(name: "Normal Texture", kind: .Inlet)
        self.outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)
        
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

        case inputDiffuseTexturePort
        case inputNormalTexturePort
        case outputMaterialPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputBaseColor, forKey: .inputBaseColorParameter)
        try container.encode(self.inputEmissiveColor, forKey: .inputEmissiveColorParameter)
        try container.encode(self.inputSpecular, forKey: .inputSpecularParameter)
        try container.encode(self.inputRoughness, forKey: .inputRoughnessParameter)
        try container.encode(self.inputMetallic, forKey: .inputMetallicParameter)
        try container.encode(self.inputOcclusion, forKey: .inputOcclusionParameter)

        try container.encode(self.inputDiffuseTexture, forKey: .inputDiffuseTexturePort)
        try container.encode(self.inputNormalTexture, forKey: .inputNormalTexturePort)
        try container.encode(self.outputMaterial, forKey: .outputMaterialPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)


        self.inputBaseColor = try container.decode(Float4Parameter.self, forKey: .inputBaseColorParameter)
        self.inputEmissiveColor = try container.decode(Float4Parameter.self, forKey: .inputEmissiveColorParameter)
        self.inputSpecular = try container.decode(FloatParameter.self, forKey: .inputSpecularParameter)
        self.inputRoughness = try container.decode(FloatParameter.self, forKey: .inputRoughnessParameter)
        self.inputMetallic = try container.decode(FloatParameter.self, forKey: .inputMetallicParameter)
        self.inputOcclusion = try container.decode(FloatParameter.self, forKey: .inputOcclusionParameter)

        self.inputDiffuseTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputDiffuseTexturePort)
        self.inputNormalTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputNormalTexturePort)

        self.outputMaterial = try container.decode(NodePort<Material>.self, forKey: .outputMaterialPort)
        
        try super.init(from: decoder)
    }
    
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
        self.evaluate(material: self.material, atTime: atTime)

        self.material.baseColor = self.inputBaseColor.value
        self.material.emissiveColor = self.inputEmissiveColor.value
        
        self.material.specular = self.inputSpecular.value
        self.material.metallic = self.inputMetallic.value
        self.material.roughness = self.inputRoughness.value
        self.material.occlusion = self.inputOcclusion.value
        
        
        if let tex = self.inputDiffuseTexture.value
        {
            self.material.setTexture(tex.texture, type: .baseColor)
        }
        
        if let tex = self.inputNormalTexture.value
        {
            self.material.setTexture(tex.texture, type: .normal)
        }
        
//        if let tex = self.inputHardness.value
//        {
//            self.material.ha = tex
//        }
        
//        self.material.color = simd_float4( cosf(Float(atTime.remainder(dividingBy: 1) )  * Float.pi ) , 0.0, 0.0, 1.0)

        
        self.outputMaterial.send(self.material)
     }
}
