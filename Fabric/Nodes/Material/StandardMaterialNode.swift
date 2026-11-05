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
    public override class var name:String {  "Physical Material" }
    override public class var nodeDescription: String { "Provides a Physically Based Rendering Material supporting basic PBR rendering like Diffuse, Normal, Specular, Metallic, and Emissive Images and properties."}

    // Ports
    public let inputDiffuseTexture = NodePort<FabricImage>(name: "Diffuse Texture", kind: .Inlet, description: "Base color/albedo texture map")
    public let inputNormalTexture = NodePort<FabricImage>(name: "Normal Texture", kind: .Inlet, description: "Normal map for surface detail")
    public let inputEmissiveTexture = NodePort<FabricImage>(name: "Emissive Texture", kind: .Inlet, description: "Emission/glow texture map")
    public let inputSpecularTexture = NodePort<FabricImage>(name: "Specular Texture", kind: .Inlet, description: "Specular intensity texture map")
    public let inputRoughnessTexture = NodePort<FabricImage>(name: "Roughness Texture", kind: .Inlet, description: "Surface roughness texture map")
    public let inputMetallicTexture = NodePort<FabricImage>(name: "Metallic Texture", kind: .Inlet, description: "Metallic property texture map")
    public let inputBaseColor = ParameterPort(parameter:Float4Parameter("Base Color", simd_float4(repeating:1), .colorpicker, "Base diffuse color of the material (RGBA)"))
    public let inputEmissiveColor = ParameterPort(parameter:Float4Parameter("Emissive Color", simd_float4(repeating:0), .colorpicker, "Self-illumination color independent of lighting (RGBA)"))
    public let inputSpecular = ParameterPort(parameter:FloatParameter("Specular", 0.25, 0.0, 1.0, .slider, "Intensity of specular highlights (0 = none, 1 = full)"))
    public let inputRoughness = ParameterPort(parameter:FloatParameter("Roughness", 0.25, 0.0, 1.0, .slider, "Surface roughness where 0 is smooth and 1 is fully rough"))
    public let inputMetallic = ParameterPort(parameter:FloatParameter("Metallic", 0.75, 0.0, 1.0, .slider, "Metallic property where 0 is dielectric and 1 is pure metal"))
    public let inputOcclusion = ParameterPort(parameter:FloatParameter("Occlusion", 0.75, 0.0, 1.0, .slider, "Ambient occlusion factor to darken crevices (0-1)"))
    public let inputEnvironmentIntensity = ParameterPort(parameter:FloatParameter("Environment Intensity", 1.0, 0.0, 1.0, .slider, "Strength of environment map reflections (0-1)"))
    public let inputGammaCorrection = ParameterPort(parameter:FloatParameter("Gamma Correction", 1.0, 0.0, 2.4, .slider, "Gamma correction value for color space conversion"))
    public let inputPointSize = ParameterPort(parameter:FloatParameter("Point Size", 1.0, 0.5, 64.0, .slider, "Point Size") )

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputDiffuseTexture", port: self.inputDiffuseTexture),
            PortDeclaration(key: "inputNormalTexture", port: self.inputNormalTexture),
            PortDeclaration(key: "inputEmissiveTexture", port: self.inputEmissiveTexture),
            PortDeclaration(key: "inputSpecularTexture", port: self.inputSpecularTexture),
            PortDeclaration(key: "inputRoughnessTexture", port: self.inputRoughnessTexture),
            PortDeclaration(key: "inputMetallicTexture", port: self.inputMetallicTexture),
            PortDeclaration(key: "inputBaseColor", port: self.inputBaseColor),
            PortDeclaration(key: "inputEmissiveColor", port: self.inputEmissiveColor),
            PortDeclaration(key: "inputSpecular", port: self.inputSpecular),
            PortDeclaration(key: "inputRoughness", port: self.inputRoughness),
            PortDeclaration(key: "inputMetallic", port: self.inputMetallic),
            PortDeclaration(key: "inputOcclusion", port: self.inputOcclusion),
            PortDeclaration(key: "inputEnvironmentIntensity", port: self.inputEnvironmentIntensity),
            PortDeclaration(key: "inputGammaCorrection", port: self.inputGammaCorrection),
            PortDeclaration(key: "inputPointSize", port: self.inputPointSize),
        ] + super.declaredPorts()
    }

    public override var material: StandardMaterial {
        return _material
    }
    
    private lazy var _material = StandardMaterial(context:self.context)

    func setImage(_ image: FabricImage?, for textureType: PBRTextureType)
    {
        self.material.setTexture(image?.texture, type: textureType)
        self.material.setTextureTransform(image?.textureTransform ?? matrix_identity_float4x4,
                                          type: textureType)
    }
    
    public override func evaluate(material: Material, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)
     
        if self.inputBaseColor.valueDidChange,
           let inputBaseColor = self.inputBaseColor.value
        {
            self.material.baseColor = inputBaseColor
            shouldOutput = true
        }
        
        if self.inputEmissiveColor.valueDidChange,
            let inputEmissiveColor = self.inputEmissiveColor.value
        {
            self.material.emissiveColor = inputEmissiveColor
            shouldOutput = true
        }
        
        if self.inputSpecular.valueDidChange,
            let inputSpecular = self.inputSpecular.value
        {
            self.material.specular = inputSpecular
            shouldOutput = true
        }
        
        if self.inputMetallic.valueDidChange,
            let inputMetallic = self.inputMetallic.value
        {
            self.material.metallic = inputMetallic
            shouldOutput = true
        }
        
        if self.inputRoughness.valueDidChange,
            let inputRoughness = self.inputRoughness.value
        {
            self.material.roughness = inputRoughness
            shouldOutput = true
        }
        
        if self.inputOcclusion.valueDidChange,
            let inputOcclusion = self.inputOcclusion.value
        {
            self.material.occlusion = inputOcclusion
            shouldOutput = true
        }

        if self.inputEnvironmentIntensity.valueDidChange,
            let inputEnvironmentIntensity = self.inputEnvironmentIntensity.value
        {
            self.material.environmentIntensity = inputEnvironmentIntensity
            shouldOutput = true
        }
        
        if self.inputGammaCorrection.valueDidChange,
            let inputGammaCorrection = self.inputGammaCorrection.value
        {
            self.material.gammaCorrection = inputGammaCorrection
            shouldOutput = true
        }

        if self.inputDiffuseTexture.valueDidChange
        {
            self.setImage(self.inputDiffuseTexture.value, for: .baseColor)
            shouldOutput = true
        }
        
        if self.inputNormalTexture.valueDidChange
        {
            self.setImage(self.inputNormalTexture.value, for: .normal)
            shouldOutput = true
        }

        if self.inputEmissiveTexture.valueDidChange
        {
            self.setImage(self.inputEmissiveTexture.value, for: .emissive)
            shouldOutput = true
        }

        if self.inputSpecularTexture.valueDidChange
        {
            self.setImage(self.inputSpecularTexture.value, for: .specular)
            shouldOutput = true
        }

        if self.inputRoughnessTexture.valueDidChange
        {
            self.setImage(self.inputRoughnessTexture.value, for: .roughness)
            shouldOutput = true
        }
        
        if self.inputMetallicTexture.valueDidChange
        {
            self.setImage(self.inputMetallicTexture.value, for: .metallic)
            shouldOutput = true
        }
//        self.material.setTexture(self.inputBumpTexture.value?.texture, type: .displacement)
//        self.material.setTexture(self.inputOcclusionTexture.value?.texture, type: .occlusion)

        if self.inputPointSize.valueDidChange,
           let inputPointSize = self.inputPointSize.value
        {
            shouldOutput = true
            self.material.pointSize = inputPointSize
        }
        
        return shouldOutput
    }
}
