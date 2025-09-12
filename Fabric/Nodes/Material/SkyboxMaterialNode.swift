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

public class SkyboxMaterialNode : BaseMaterialNode
{
    public override class var name:String {  "Skybox Material" }

    // Parameters
    public let inputEnvironmentIntensity:FloatParameter
    public let inputBlur:FloatParameter
    public override var inputParameters: [any Parameter] { [inputEnvironmentIntensity, inputBlur] + super.inputParameters }
    
    
    public override var material: SkyboxMaterial {
        return _material
    }
    
    private var _material = SkyboxMaterial()
    
    public required init(context:Context)
    {
        // self.inputTexture =  NodePort<EquatableTexture>(name: "Texture", kind: .Inlet)
        self.inputEnvironmentIntensity = FloatParameter("Environment Intensity", 1.0, 0.0, 1.0, .slider)
        self.inputBlur = FloatParameter("Blur", 0.0, 0.0, 5.0, .slider)
        super.init(context: context)
        
        self.material.setup()
        
//        self.material.color = simd_float4(1.0, 0.0, 0.0, 1.0)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputTexturePort
        case inputEnvironmentIntensityParameter
        case inputBlurParameter
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.inputEnvironmentIntensity = try container.decode(FloatParameter.self, forKey: .inputEnvironmentIntensityParameter)
        self.inputBlur = try container.decode(FloatParameter.self, forKey: .inputBlurParameter)
        
        try super.init(from: decoder)
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputEnvironmentIntensity, forKey: .inputEnvironmentIntensityParameter)
        try container.encode(self.inputBlur, forKey: .inputBlurParameter)
        
        try super.encode(to: encoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.evaluate(material: self.material, atTime: context.timing.time)

        if self.inputEnvironmentIntensity.valueDidChange
        {
            self.material.environmentIntensity = self.inputEnvironmentIntensity.value
        }
        
        if  self.inputBlur.valueDidChange
        {
            self.material.blur = self.inputBlur.value
        }
        
        self.outputMaterial.send(self.material)
     }
}
