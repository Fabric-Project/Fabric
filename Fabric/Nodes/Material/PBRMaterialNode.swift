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

public class PBRMaterialNode : StandardMaterialNode
{
    override public class var name:String {  "Advanced Physical Material" }
    override public class var nodeDescription: String { "Provides a Advanced Physically Based Rendering Material supporting PBR rendering like Diffuse, Normal, Specular, Metallic, Clear Coat, Sheen, Transmission, IOR Images and Properties."}

    
    // Ports
    let inputBumpTexture = NodePort<FabricImage>(name: "Bump Texture", kind: .Inlet, description: "Bump map for surface height detail")
    let inputDisplacementTexture = NodePort<FabricImage>(name: "Displacement Texture", kind: .Inlet, description: "Displacement map for vertex offset")
    let inputOcclusionTexture = NodePort<FabricImage>(name: "Occlusion Texture", kind: .Inlet, description: "Ambient occlusion texture map")
    let inputSubsurfaceTexture = NodePort<FabricImage>(name: "Subsurface Texture", kind: .Inlet, description: "Subsurface scattering texture map")
    let inputClearcoatTexture = NodePort<FabricImage>(name: "Clearcoat Texture", kind: .Inlet, description: "Clear coat intensity texture map")
    let inputClearcoatRoughTexture = NodePort<FabricImage>(name: "Clearcoat Roughness Texture", kind: .Inlet, description: "Clear coat roughness texture map")
    let inputClearcoatGlossTexture = NodePort<FabricImage>(name: "Clearcoat Gloss Texture", kind: .Inlet, description: "Clear coat gloss texture map")
    let inputTransmissionTexture = NodePort<FabricImage>(name: "Transmission Texture", kind: .Inlet, description: "Light transmission texture map")
    let inputSubsurface = ParameterPort(parameter:FloatParameter("Sub Surface", 0.0, 0.0, 1.0, .slider, "Subsurface scattering intensity for translucent materials"))
    let inputAnisotropic = ParameterPort(parameter:FloatParameter("Anisotropic", 0.0, -1.0, 1.0, .slider, "Anisotropic reflection strength (-1 to 1)"))
    let inputAnisotropicAngle = ParameterPort(parameter:FloatParameter("Anisotropic Angle", 0.0, -1.0, 1.0, .slider, "Rotation angle for anisotropic reflections"))
    let inputSpecularTint = ParameterPort(parameter:FloatParameter("Specular Tint", 0.0, 0.0, 1.0, .slider, "Tints specular reflections with the base color"))
    let inputClearcoat = ParameterPort(parameter:FloatParameter("Clearcoat", 0.0, 0.0, 1.0, .slider, "Intensity of the clear coat layer (0 = none, 1 = full)"))
    let inputClearcoatRoughness = ParameterPort(parameter:FloatParameter("Clearcoat Roughness", 0.0, 0.0, 1.0, .slider, "Roughness of the clear coat layer"))
    let inputSheen = ParameterPort(parameter:FloatParameter("Sheen", 0.0, 0.0, 1.0, .slider, "Sheen intensity for fabric-like materials"))
    let inputSheenTint = ParameterPort(parameter:FloatParameter("Sheen Tint", 0.0, 0.0, 1.0, .slider, "Tints sheen reflections with the base color"))
    let inputTransmission = ParameterPort(parameter:FloatParameter("Transmission", 0.0, 0.0, 1.0, .slider, "Light transmission for glass-like materials (0-1)"))
    let inputThickness = ParameterPort(parameter:FloatParameter("Thickness", 1.0, 0.0, 5.0, .slider, "Thickness of the material for transmission calculations"))
    let inputIOR = ParameterPort(parameter:FloatParameter("Index of Refraction", 1.5, 0.0, 3.0, .slider, "Index of refraction (1.0 = air, 1.5 = glass, 2.4 = diamond)"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputBumpTexture", port: self.inputBumpTexture),
            PortDeclaration(key: "inputDisplacementTexture", port: self.inputDisplacementTexture),
            PortDeclaration(key: "inputOcclusionTexture", port: self.inputOcclusionTexture),
            PortDeclaration(key: "inputSubsurfaceTexture", port: self.inputSubsurfaceTexture),
            PortDeclaration(key: "inputClearcoatTexture", port: self.inputClearcoatTexture),
            PortDeclaration(key: "inputClearcoatRoughTexture", port: self.inputClearcoatRoughTexture),
            PortDeclaration(key: "inputClearcoatGlossTexture", port: self.inputClearcoatGlossTexture),
            PortDeclaration(key: "inputTransmissionTexture", port: self.inputTransmissionTexture),
            PortDeclaration(key: "inputSubsurface", port: self.inputSubsurface),
            PortDeclaration(key: "inputAnisotropic", port: self.inputAnisotropic),
            PortDeclaration(key: "inputAnisotropicAngle", port: self.inputAnisotropicAngle),
            PortDeclaration(key: "inputSpecularTint", port: self.inputSpecularTint),
            PortDeclaration(key: "inputClearcoat", port: self.inputClearcoat),
            PortDeclaration(key: "inputClearcoatRoughness", port: self.inputClearcoatRoughness),
            PortDeclaration(key: "inputSheen", port: self.inputSheen),
            PortDeclaration(key: "inputSheenTint", port: self.inputSheenTint),
            PortDeclaration(key: "inputTransmission", port: self.inputTransmission),
            PortDeclaration(key: "inputThickness", port: self.inputThickness),
            PortDeclaration(key: "inputIOR", port: self.inputIOR),
        ]
    }

    override public var material: PhysicalMaterial {
        return _material
    }
    
    private lazy var _material = PhysicalMaterial(context:self.context)

    override public func evaluate(material: Material, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)
                
        if self.inputSubsurface.valueDidChange,
           let inputSubsurface = self.inputSubsurface.value
        {
            self.material.subsurface = inputSubsurface
            shouldOutput = true
        }
        
        if self.inputAnisotropic.valueDidChange,
           let inputAnisotropic = self.inputAnisotropic.value
        {
            self.material.anisotropic = inputAnisotropic
            shouldOutput = true
        }
        
        if self.inputAnisotropicAngle.valueDidChange,
           let inputAnisotropicAngle = self.inputAnisotropicAngle.value
        {
            self.material.anisotropicAngle = inputAnisotropicAngle
            shouldOutput = true
        }
        
        if self.inputSpecularTint.valueDidChange,
           let inputSpecularTint = self.inputSpecularTint.value
        {
            self.material.specularTint = inputSpecularTint
            shouldOutput = true
        }
        
        if self.inputClearcoat.valueDidChange,
           let inputClearcoat = self.inputClearcoat.value
        {
            self.material.clearcoat = inputClearcoat
            shouldOutput = true
        }
        
        if self.inputClearcoatRoughness.valueDidChange,
           let inputClearcoatRoughness = self.inputClearcoatRoughness.value
        {
            self.material.clearcoatRoughness = inputClearcoatRoughness
            shouldOutput = true
        }
        
        if self.inputSheen.valueDidChange,
           let inputSheen = self.inputSheen.value
        {
            self.material.sheen = inputSheen
            shouldOutput = true
        }
        
        if self.inputSheenTint.valueDidChange,
           let inputSheenTint = self.inputSheenTint.value
        {
            self.material.sheenTint = inputSheenTint
            shouldOutput = true
        }
        
        if self.inputTransmission.valueDidChange,
           let inputTransmission = self.inputTransmission.value
        {
            self.material.transmission = inputTransmission
            shouldOutput = true
        }
        
        if self.inputOcclusion.valueDidChange,
           let inputOcclusion = self.inputOcclusion.value
        {
            self.material.occlusion = inputOcclusion
            shouldOutput = true
        }
        
        if self.inputThickness.valueDidChange,
           let inputThickness = self.inputThickness.value
        {
            self.material.thickness = inputThickness
            shouldOutput = true
        }
        
        if self.inputIOR.valueDidChange,
           let inputIOR = self.inputIOR.value
        {
            self.material.ior = inputIOR
            shouldOutput = true
        }
        
        if self.inputBumpTexture.valueDidChange
        {
            self.setImage(self.inputBumpTexture.value, for: .bump)
            shouldOutput = true
        }
        
        if self.inputDisplacementTexture.valueDidChange
        {
            self.setImage(self.inputDisplacementTexture.value, for: .displacement)
            shouldOutput = true
        }
        
        if self.inputOcclusionTexture.valueDidChange
        {
            self.setImage(self.inputOcclusionTexture.value, for: .occlusion)
            shouldOutput = true
        }
        
        if self.inputSubsurfaceTexture.valueDidChange
        {
            self.setImage(self.inputSubsurfaceTexture.value, for: .subsurface)
            shouldOutput = true
        }
        
        if self.inputClearcoatTexture.valueDidChange
        {
            self.setImage(self.inputClearcoatTexture.value, for: .clearcoat)
            shouldOutput = true
        }
        
        if self.inputClearcoatRoughTexture.valueDidChange
        {
            self.material.setTexture(self.inputClearcoatRoughTexture.value?.texture, type: .clearcoatRoughness)
            shouldOutput = true
        }
        
        if self.inputClearcoatGlossTexture.valueDidChange
        {
            self.material.setTexture(self.inputClearcoatGlossTexture.value?.texture, type: .clearcoatGloss)
            shouldOutput = true
        }

        if self.inputClearcoatRoughTexture.valueDidChange || self.inputClearcoatGlossTexture.valueDidChange
        {
            let clearcoatSurfaceImage = self.inputClearcoatRoughTexture.value ?? self.inputClearcoatGlossTexture.value
            self.material.setTextureTransform(clearcoatSurfaceImage?.textureTransform ?? matrix_identity_float4x4,
                                              type: .clearcoatRoughness)
        }
        
        if self.inputTransmissionTexture.valueDidChange
        {
            self.setImage(self.inputTransmissionTexture.value, for: .transmission)
            shouldOutput = true
        }
        
        return shouldOutput
    }
}
