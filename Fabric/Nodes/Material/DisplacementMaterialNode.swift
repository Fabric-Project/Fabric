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
    public override var inputParameters: [any Parameter] {
        [
        self.inputAmount,
        self.inputLumaVsRGBAmount,
        self.inputMinPointSize,
        self.inputMaxPointSize,
        self.inputBrightness] + super.inputParameters
    }
    
    // Ports
    public let inputTexture:NodePort<EquatableTexture>
    public let inputDisplacementTexture:NodePort<EquatableTexture>
    public let inputPointSpriteTexture:NodePort<EquatableTexture>
    public override var ports: [any NodePortProtocol] {   [
        self.inputTexture,
        self.inputDisplacementTexture,
        self.inputPointSpriteTexture] + super.ports
    }
    
    
    public override var material: DisplacementMaterial {
        return _material
    }
    
    private var _material:DisplacementMaterial
    
//    private var depthStencilDescriptor:MTLDepthStencilDescriptor
        
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

//        self.depthStencilDescriptor = Self.setupDepthStencil()

        super.init(context: context)

        self.material.setup()

//        self.material.depthStencilState = context.device.makeDepthStencilState(descriptor: self.depthStencilDescriptor)
//        self.material.onBind = { renderEncoder in
//            renderEncoder.setStencilReferenceValue(99)
//        }
        
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
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
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

//        self.depthStencilDescriptor = Self.setupDepthStencil()

        try super.init(from: decoder)

        self.material.context = decodeContext.documentContext
//        self.material.setup()

//        self.material.blending = .additive
//        self.material.rgbBlendOperation = .add
//        self.material.depthWriteEnabled = false
//        self.material.depthCompareFunction = .always
//        self.material.blending
//        
//        self.material.onBind = { renderEncoder in
//            renderEncoder.setStencilReferenceValue(127)
//        }
        
    }
    
    class private func setupDepthStencil() -> MTLDepthStencilDescriptor
    {
        let stencil = MTLStencilDescriptor()
        stencil.stencilCompareFunction = .greaterEqual           // Pass if current count <= 4
        stencil.stencilFailureOperation = .keep             // If stencil test fails
        stencil.depthFailureOperation = .keep               // If depth test fails
        stencil.depthStencilPassOperation = .incrementClamp // If both pass: increment

        let depthStencil = MTLDepthStencilDescriptor()
        depthStencil.frontFaceStencil = stencil
        depthStencil.backFaceStencil = stencil
        depthStencil.isDepthWriteEnabled = false            // Optional with blending
        depthStencil.depthCompareFunction = .always

        depthStencil.label = "DisplacementMaterialNode.depthStencil"
        return depthStencil
        
//        let stencil = MTLStencilDescriptor()
//        stencil.writeMask = 0xFF
//        stencil.readMask = 0xFF
//        stencil.stencilCompareFunction = .never
//        stencil.stencilFailureOperation = .replace
//        stencil.depthFailureOperation = .replace               // If depth test fails
//        stencil.depthStencilPassOperation = .replace // If both pass: increment
//
//
//        let depthStencil = MTLDepthStencilDescriptor()
//        depthStencil.frontFaceStencil = stencil
//        depthStencil.backFaceStencil = stencil
//        depthStencil.isDepthWriteEnabled = false
//        depthStencil.depthCompareFunction = .always
//        depthStencil.label = "DisplacementMaterialNode.depthStencil"

//        return depthStencil
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

//        renderPassDescriptor.stencilAttachment.loadAction = .clear
//        renderPassDescriptor.stencilAttachment.storeAction = .store
//        renderPassDescriptor.stencilAttachment.clearStencil = 0

        self.evaluate(material: self.material, atTime: context.timing.time)

//        self.material.depthStencilState = context.context.device.makeDepthStencilState(descriptor: self.depthStencilDescriptor)

//        assert(renderPassDescriptor.stencilAttachment.texture != nil)
//        assert(renderPassDescriptor.stencilAttachment.texture?.pixelFormat != .invalid)
//        assert(renderPassDescriptor.stencilAttachment.loadAction == .clear)
//        assert(renderPassDescriptor.stencilAttachment.storeAction == .store)
//        assert(renderPassDescriptor.stencilAttachment.clearStencil == 0)
        
//        assert(self.material.depthStencilState != nil)
        
        
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
