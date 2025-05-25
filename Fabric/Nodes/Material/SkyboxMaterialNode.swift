//
//  SkyboxMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//



import Foundation
import Satin
import simd
import Metal

class SkyboxMaterialNode : BaseMaterialNode
{
    override class var name:String {  "Skybox Material" }

    // Parameters
    let inputEnvironmentIntensity:FloatParameter
    let inputBlur:FloatParameter
    override var inputParameters: [any Parameter] { [inputEnvironmentIntensity, inputBlur] + super.inputParameters }
    
    // Ports

    // I cant tell if this is a good idea
    // We can either use the Scene Builder or an Dedicated Environment node?
    // Hrm?
    
//    let inputTexture:NodePort<EquatableTexture> = NodePort<EquatableTexture>(name: "Texture", kind: .Inlet)
    let outputMaterial:NodePort<Material>
    override var ports: [any NodePortProtocol] {  super.ports + [outputMaterial] }

    private let material = SkyboxMaterial()

    required init(context:Context)
    {
        // self.inputTexture =  NodePort<EquatableTexture>(name: "Texture", kind: .Inlet)
        self.inputEnvironmentIntensity = FloatParameter("Environment Intensity", 1.0, 0.0, 1.0, .slider)
        self.inputBlur = FloatParameter("Blur", 0.0, 0.0, 5.0, .slider)
        self.outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)
        super.init(context: context)
        
        self.material.setup()
        
//        self.material.color = simd_float4(1.0, 0.0, 0.0, 1.0)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputTexturePort
        case inputEnvironmentIntensityParameter
        case inputBlurParameter
        case outputMaterialPort
    }

    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.inputEnvironmentIntensity = try container.decode(FloatParameter.self, forKey: .inputEnvironmentIntensityParameter)
        self.inputBlur = try container.decode(FloatParameter.self, forKey: .inputBlurParameter)
        self.outputMaterial = try container.decode(NodePort<Material>.self, forKey: .outputMaterialPort)
        
        try super.init(from: decoder)
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputEnvironmentIntensity, forKey: .inputEnvironmentIntensityParameter)
        try container.encode(self.inputBlur, forKey: .inputBlurParameter)
        try container.encode(self.outputMaterial, forKey: .outputMaterialPort)
        
        try super.encode(to: encoder)
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
       
        self.evaluate(material: self.material, atTime: atTime)

        self.material.environmentIntensity = self.inputEnvironmentIntensity.value
        self.material.blur = self.inputBlur.value
        
        self.outputMaterial.send(self.material)
     }
}
