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
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return [
            ("inputDiffuseTexture",  NodePort<FabricImage>(name: "Diffuse Texture", kind: .Inlet, description: "Base color/albedo texture map")),
            ("inputNormalTexture",  NodePort<FabricImage>(name: "Normal Texture", kind: .Inlet, description: "Normal map for surface detail")),
            ("inputEmissiveTexture",  NodePort<FabricImage>(name: "Emissive Texture", kind: .Inlet, description: "Emission/glow texture map")),
            ("inputSpecularTexture",  NodePort<FabricImage>(name: "Specular Texture", kind: .Inlet, description: "Specular intensity texture map")),
            ("inputRoughnessTexture",  NodePort<FabricImage>(name: "Roughness Texture", kind: .Inlet, description: "Surface roughness texture map")),
            ("inputMetallicTexture",  NodePort<FabricImage>(name: "Metallic Texture", kind: .Inlet, description: "Metallic property texture map")),
            ("inputBaseColor",  ParameterPort(parameter:Float4Parameter("Base Color", simd_float4(repeating:1), .colorpicker, "Base diffuse color of the material (RGBA)"))),
            ("inputEmissiveColor",  ParameterPort(parameter:Float4Parameter("Emissive Color", simd_float4(repeating:0), .colorpicker, "Self-illumination color independent of lighting (RGBA)"))),
            ("inputSpecular",  ParameterPort(parameter:FloatParameter("Specular", 0.25, 0.0, 1.0, .slider, "Intensity of specular highlights (0 = none, 1 = full)"))),
            ("inputRoughness",  ParameterPort(parameter:FloatParameter("Roughness", 0.25, 0.0, 1.0, .slider, "Surface roughness where 0 is smooth and 1 is fully rough"))),
            ("inputMetallic",  ParameterPort(parameter:FloatParameter("Metallic", 0.75, 0.0, 1.0, .slider, "Metallic property where 0 is dielectric and 1 is pure metal"))),
            ("inputOcclusion",  ParameterPort(parameter:FloatParameter("Occlusion", 0.75, 0.0, 1.0, .slider, "Ambient occlusion factor to darken crevices (0-1)"))),
            ("inputEnvironmentIntensity",  ParameterPort(parameter:FloatParameter("Environment Intensity", 1.0, 0.0, 1.0, .slider, "Strength of environment map reflections (0-1)"))),
            ("inputGammaCorrection",  ParameterPort(parameter:FloatParameter("Gamma Correction", 1.0, 0.0, 2.4, .slider, "Gamma correction value for color space conversion"))),
            ]
        + ports
    }

    // Proxy Ports
    public var inputDiffuseTexture: NodePort<FabricImage> { port(named: "inputDiffuseTexture") }
    public var inputNormalTexture: NodePort<FabricImage> { port(named: "inputNormalTexture") }
    public var inputEmissiveTexture: NodePort<FabricImage>{ port(named: "inputEmissiveTexture") }
    public var inputSpecularTexture: NodePort<FabricImage>{ port(named: "inputSpecularTexture") }
    public var inputRoughnessTexture: NodePort<FabricImage>{ port(named: "inputRoughnessTexture") }
    public var inputMetallicTexture: NodePort<FabricImage>{ port(named: "inputMetallicTexture") }
    public var inputBaseColor: ParameterPort<simd_float4>{ port(named: "inputBaseColor") }
    public var inputEmissiveColor: ParameterPort<simd_float4>{ port(named: "inputEmissiveColor") }
    public var inputSpecular: ParameterPort<Float>{ port(named: "inputSpecular") }
    public var inputRoughness: ParameterPort<Float>{ port(named: "inputRoughness") }
    public var inputMetallic: ParameterPort<Float>{ port(named: "inputMetallic") }
    public var inputOcclusion: ParameterPort<Float>{ port(named: "inputOcclusion") }
    public var inputEnvironmentIntensity: ParameterPort<Float>{ port(named: "inputEnvironmentIntensity") }
    public var inputGammaCorrection: ParameterPort<Float>{ port(named: "inputGammaCorrection") }
    
    
    public override var material: StandardMaterial {
        return _material
    }
    
    private var _material = StandardMaterial()
    
   
    
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
            self.material.setTexture(self.inputDiffuseTexture.value?.texture, type: .baseColor)
            shouldOutput = true
        }
        
        if self.inputNormalTexture.valueDidChange
        {
            self.material.setTexture(self.inputNormalTexture.value?.texture, type: .normal)
            shouldOutput = true
        }

        if self.inputEmissiveTexture.valueDidChange
        {
            self.material.setTexture(self.inputEmissiveTexture.value?.texture, type: .emissive)
            shouldOutput = true
        }

        if self.inputSpecularTexture.valueDidChange
        {
            self.material.setTexture(self.inputSpecularTexture.value?.texture, type: .specular)
            shouldOutput = true
        }

        if self.inputRoughnessTexture.valueDidChange
        {
            self.material.setTexture(self.inputRoughnessTexture.value?.texture, type: .roughness)
            shouldOutput = true
        }
        
        if self.inputMetallicTexture.valueDidChange
        {
            self.material.setTexture(self.inputMetallicTexture.value?.texture, type: .metallic)
            shouldOutput = true
        }
//        self.material.setTexture(self.inputBumpTexture.value?.texture, type: .displacement)
//        self.material.setTexture(self.inputOcclusionTexture.value?.texture, type: .occlusion)

        return shouldOutput
    }
}
