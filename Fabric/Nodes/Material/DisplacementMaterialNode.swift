//
//  DisplacementMaterial.swift
//  Fabric
//
//  Created by Anton Marini on 7/4/25.
//

import Foundation
import Satin
import simd
import Metal

public class DisplacementMaterialNode: BaseMaterialNode
{
    public class DisplacementMaterial : SourceMaterial { }
    
    public override class var name:String {  "Displacement Material" }

    // Params
    public let inputAmount:FloatParameter
    public let inputLumaVsRGBAmount:FloatParameter
    public let inputMinPointSize:FloatParameter
    public let inputMaxPointSize:FloatParameter
    public let inputBrightness:FloatParameter
    public override var inputParameters: [any Parameter] { super.inputParameters +
        [
        self.inputAmount,
        self.inputLumaVsRGBAmount,
        self.inputMinPointSize,
        self.inputMaxPointSize,
        self.inputBrightness]
    }
    
    // Ports
    public let inputTexture:NodePort<EquatableTexture>
    public let inputDisplacementTexture:NodePort<EquatableTexture>
    public let inputPointSpriteTexture:NodePort<EquatableTexture>
    public override var ports: [any NodePortProtocol] {  super.ports + [
        self.inputTexture,
        self.inputDisplacementTexture,
        self.inputPointSpriteTexture]
    }
    
    
    public override var material: DisplacementMaterial {
        return _material
    }
    
    private var _material:DisplacementMaterial
    
    required public init(context: Context)
    {
        let bundle = Bundle(for: Self.self)
        let shaderURL = bundle.url(forResource: "DisplacementMaterial", withExtension: "metal", subdirectory: "Shaders")
        
        self._material = DisplacementMaterial(pipelineURL: shaderURL!)

        self.inputAmount = FloatParameter("Amount", 0.0, 0.0, 2.0, .slider)
        self.inputLumaVsRGBAmount = FloatParameter("Luma v RGB", 0.0, 0.0, 1.0, .slider)
        self.inputMinPointSize = FloatParameter("Min PointSize", 1.0, 0.5, 128.0, .slider)
        self.inputMaxPointSize = FloatParameter("Max PointSize", 1.0, 0.5, 128.0, .slider)
        self.inputBrightness = FloatParameter("Brightness", 1.0, 0.0, 2.0, .slider)

        self.inputTexture = NodePort<EquatableTexture>(name: "Texture", kind: .Inlet)
        self.inputDisplacementTexture = NodePort<EquatableTexture>(name: "Displacement Texture", kind: .Inlet)
        self.inputPointSpriteTexture = NodePort<EquatableTexture>(name: "Point Sprite Texture", kind: .Inlet)

        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputTexturePort
        case inputDisplacementTexturePort
        case inputPointSpriteTexturePort
        case inputAmountParameter
        case inputLumaVRGBAmountParameter
        case inputMinPointSizeParameter
        case inputMaxPointSizeParameter
        case inputBrightnessParameter
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let bundle = Bundle(for: Self.self)
        let shaderURL = bundle.url(forResource: "DisplacementMaterial", withExtension: "metal", subdirectory: "Shaders")
        
        self._material = DisplacementMaterial(pipelineURL: shaderURL!)
        
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputAmount = try container.decode(FloatParameter.self, forKey: .inputAmountParameter)
        self.inputLumaVsRGBAmount = try container.decode(FloatParameter.self, forKey: .inputLumaVRGBAmountParameter)
        self.inputMinPointSize = try container.decode(FloatParameter.self, forKey: .inputMinPointSizeParameter)
        self.inputMaxPointSize = try container.decode(FloatParameter.self, forKey: .inputMaxPointSizeParameter)
        self.inputBrightness = try container.decode(FloatParameter.self, forKey: .inputBrightnessParameter)

        self.inputTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputTexturePort)
        self.inputDisplacementTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputDisplacementTexturePort)
        self.inputPointSpriteTexture = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputPointSpriteTexturePort)

        try super.init(from: decoder)
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputAmount, forKey: .inputAmountParameter)
        try container.encode(self.inputLumaVsRGBAmount, forKey: .inputLumaVRGBAmountParameter)
        try container.encode(self.inputMinPointSize, forKey: .inputMinPointSizeParameter)
        try container.encode(self.inputMaxPointSize, forKey: .inputMaxPointSizeParameter)
        try container.encode(self.inputBrightness, forKey: .inputBrightnessParameter)
        try container.encode(self.inputTexture, forKey: .inputTexturePort)
        try container.encode(self.inputDisplacementTexture, forKey: .inputDisplacementTexturePort)
        try container.encode(self.inputPointSpriteTexture, forKey: .inputPointSpriteTexturePort)

        try super.encode(to: encoder)
    }
    
    override public func execute(context: GraphExecutionContext, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: any MTLCommandBuffer) {

        self.evaluate(material: self.material, atTime: context.timing.time)
        
        if let texture = self.inputDisplacementTexture.value?.texture ?? self.inputTexture.value?.texture {
            self.material.set(texture, index: VertexTextureIndex.Custom0)
        }

        if let texture = self.inputTexture.value?.texture {
            self.material.set(texture, index: FragmentTextureIndex.Custom0)
        }
        if let texture = self.inputPointSpriteTexture.value?.texture {
            self.material.set(texture, index: FragmentTextureIndex.Custom1)
        }
        
        self.material.set("amount", self.inputAmount.value)
        self.material.set("lumaVPosMix", self.inputLumaVsRGBAmount.value)
        self.material.set("minPointSize", self.inputMinPointSize.value)
        self.material.set("maxPointSize", self.inputMaxPointSize.value)
        self.material.set("brightness", self.inputBrightness.value)

        self.outputMaterial.send(self.material)
    }
}
