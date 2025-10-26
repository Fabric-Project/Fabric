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
    override public class var nodeDescription: String { "Displace Geometry using an Images luminance or rgb values."}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return [
            ("inputTexture", NodePort<EquatableTexture>(name: "Image", kind: .Inlet)),
            ("inputDisplacementTexture", NodePort<EquatableTexture>(name: "Displacement Image", kind: .Inlet)),
            ("inputPointSpriteTexture", NodePort<EquatableTexture>(name: "Point Sprite Image", kind: .Inlet)),
            ("inputAmount", ParameterPort(parameter:FloatParameter("Amount", 0.0, 0.0, 2.0, .slider))),
            ("inputLumaVsRGBAmount", ParameterPort(parameter:FloatParameter("Luma v RGB", 0.0, 0.0, 1.0, .slider))),
            ("inputMinPointSize", ParameterPort(parameter:FloatParameter("Min PointSize", 1.0, 0.5, 128.0, .slider))),
            ("inputMaxPointSize", ParameterPort(parameter:FloatParameter("Max PointSize", 1.0, 0.5, 128.0, .slider))),
            ("inputBrightness", ParameterPort(parameter:FloatParameter("Brightness", 1.0, 0.0, 2.0, .slider))),
        ] + ports
    }

    public var inputFilePathParam:ParameterPort<String>  { port(named: "inputFilePathParam") }
    public var outputTexturePort:NodePort<EquatableTexture> { port(named: "outputTexturePort") }

    // Proxy Params
    public var inputTexture:NodePort<EquatableTexture> { port(named: "inputTexture") }
    public var inputDisplacementTexture:NodePort<EquatableTexture> { port(named: "inputDisplacementTexture") }
    public var inputPointSpriteTexture:NodePort<EquatableTexture> { port(named: "inputPointSpriteTexture") }
    public var inputAmount:ParameterPort<Float> { port(named: "inputAmount") }
    public var inputLumaVsRGBAmount:ParameterPort<Float> { port(named: "inputLumaVsRGBAmount") }
    public var inputMinPointSize:ParameterPort<Float> { port(named: "inputMinPointSize") }
    public var inputMaxPointSize:ParameterPort<Float> { port(named: "inputMaxPointSize") }
    public var inputBrightness:ParameterPort<Float> { port(named: "inputBrightness") }
    
    
    public override var material: DisplacementMaterial {
        return _material
    }
    
    private var _material:DisplacementMaterial
    
//    private var depthStencilDescriptor:MTLDepthStencilDescriptor
        
   
    required public init(context: Context)
    {
        let bundle = Bundle(for: Self.self)
        let shaderURL = bundle.url(forResource: "DisplacementMaterial", withExtension: "metal", subdirectory: "Materials")
        
        self._material = DisplacementMaterial(pipelineURL: shaderURL!)
        
        super.init(context: context)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let bundle = Bundle(for: Self.self)
        let shaderURL = bundle.url(forResource: "DisplacementMaterial", withExtension: "metal", subdirectory: "Materials")
        
        self._material = DisplacementMaterial(pipelineURL: shaderURL!)
        
        try super.init(from: decoder)
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
   
    
    override public func evaluate(material: Material, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)
        
        if self.inputDisplacementTexture.valueDidChange
        {
            if let texture = self.inputDisplacementTexture.value?.texture ?? self.inputTexture.value?.texture
            {
                self.material.set(texture, index: VertexTextureIndex.Custom0)
                shouldOutput = true
            }
        }
        
        if self.inputTexture.valueDidChange
        {
            if let texture = self.inputTexture.value?.texture
            {
                self.material.set(texture, index: FragmentTextureIndex.Custom0)
                shouldOutput = true
            }
        }
        
        if self.inputPointSpriteTexture.valueDidChange
        {
            if let texture = self.inputPointSpriteTexture.value?.texture
            {
                self.material.set(texture, index: FragmentTextureIndex.Custom1)
                shouldOutput = true
            }
        }
        
        if self.inputAmount.valueDidChange,
           let inputAmount = self.inputAmount.value
        {
            self.material.set("amount", inputAmount)
            shouldOutput = true
        }
        
        if self.inputLumaVsRGBAmount.valueDidChange,
            let inputLumaVsRGBAmount = self.inputLumaVsRGBAmount.value
        {
            self.material.set("lumaVPosMix", inputLumaVsRGBAmount)
            shouldOutput = true
        }
        
        if self.inputMinPointSize.valueDidChange,
           let inputMinPointSize = self.inputMinPointSize.value
        {
            self.material.set("minPointSize", inputMinPointSize)
            shouldOutput = true
        }
        
        if  self.inputMaxPointSize.valueDidChange,
            let inputMaxPointSize = self.inputMaxPointSize.value
        {
            self.material.set("maxPointSize", inputMaxPointSize)
            shouldOutput = true
        }
        
        if self.inputBrightness.valueDidChange,
           let inputBrightness = self.inputBrightness.value
        {
            self.material.set("brightness", inputBrightness)
            shouldOutput = true
        }
        
        return shouldOutput
    }
}
