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

class PBRMaterialNode : StandardMaterialNode
{
    override class var name:String {  "Advanced Physical Material" }

    // Params
    let inputSubsurface = FloatParameter("Sub Surface", 0.0, 0.0, 1.0, .slider)
    let inputAnisotropic = FloatParameter("Anisotropic", 0.0, -1.0, 1.0, .slider)
    let inputAnisotropicAngle = FloatParameter("Anisotropic Angle", 0.0, -1.0, 1.0, .slider)
    let inputSpecularTint = FloatParameter("Specular Tint", 0.0, 0.0, 1.0, .slider)
    let inputClearcoat = FloatParameter("Clearcoat", 0.0, 0.0, 1.0, .slider)
    let inputClearcoatRoughness = FloatParameter("Clearcoat Roughness", 0.0, 0.0, 1.0, .slider)
    let inputSheen = FloatParameter("Sheen", 0.0, 0.0, 1.0, .slider)
    let inputSheenTint = FloatParameter("Sheen Tint", 0.0, 0.0, 1.0, .slider)
    let inputTransmission = FloatParameter("Transmission", 0.0, 0.0, 1.0, .slider)
    let inputThickness = FloatParameter("Thickness", 1.0, 0.0, 5.0, .slider)
    let inputIOR = FloatParameter("Index of Refraction", 1.5, 0.0, 3.0, .slider)

    override var inputParameters: [any Parameter] {
        [
            inputSubsurface,
            inputAnisotropic,
            inputAnisotropicAngle,
            inputSpecularTint,
            inputClearcoat,
            inputClearcoatRoughness,
            inputSheen,
            inputSheenTint,
            inputTransmission,
            inputThickness,
            inputIOR,
        ] + super.inputParameters }

    // Ports
    let inputBumpTexture = NodePort<EquatableTexture>(name: "Bump Texture", kind: .Inlet)

    let inputDisplacementTexture = NodePort<EquatableTexture>(name: "Displacement Texture", kind: .Inlet)
    let inputOcclusionTexture = NodePort<EquatableTexture>(name: "Occlusion Texture", kind: .Inlet)
    let inputSubsurfaceTexture = NodePort<EquatableTexture>(name: "Subsurface Texture", kind: .Inlet)
    let inputClearcoatTexture = NodePort<EquatableTexture>(name: "Clearcoat Texture", kind: .Inlet)
    let inputClearcoatRoughTexture = NodePort<EquatableTexture>(name: "Clearcoat Roughness Texture", kind: .Inlet)
    let inputClearcoatGlossTexture = NodePort<EquatableTexture>(name: "Clearcoat Gloss Texture", kind: .Inlet)
    let inputTransmissionTexture = NodePort<EquatableTexture>(name: "Transmission Texture", kind: .Inlet)
    
    override var ports: [any NodePortProtocol] {  [
        inputBumpTexture,
        inputDisplacementTexture,
        inputOcclusionTexture,
        inputSubsurfaceTexture,
        inputClearcoatTexture,
        inputClearcoatRoughTexture,
        inputClearcoatGlossTexture,
        inputTransmissionTexture,
        ] + super.ports }
    
    override var material: PhysicalMaterial {
        return _material
    }
    
    private var _material = PhysicalMaterial()

    override func evaluate(material: Material, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)
                
        if self.inputSubsurface.valueDidChange
        {
            self.material.subsurface = self.inputSubsurface.value
            shouldOutput = true
        }
        
        if self.inputAnisotropic.valueDidChange
        {
            self.material.anisotropic = self.inputAnisotropic.value
            shouldOutput = true
        }
        
        if self.inputAnisotropicAngle.valueDidChange
        {
            self.material.anisotropicAngle = self.inputAnisotropicAngle.value
            shouldOutput = true
        }
        
        if self.inputSpecularTint.valueDidChange
        {
            self.material.specularTint = self.inputSpecularTint.value
            shouldOutput = true
        }
        
        if self.inputClearcoat.valueDidChange
        {
            self.material.clearcoat = self.inputClearcoat.value
            shouldOutput = true
        }
        
        if self.inputClearcoatRoughness.valueDidChange
        {
            self.material.clearcoatRoughness = self.inputClearcoatRoughness.value
            shouldOutput = true
        }
        
        if self.inputSheen.valueDidChange
        {
            self.material.sheen = self.inputSheen.value
            shouldOutput = true
        }
        
        if self.inputSheenTint.valueDidChange
        {
            self.material.sheenTint = self.inputSheenTint.value
            shouldOutput = true
        }
        
        if self.inputTransmission.valueDidChange
        {
            self.material.transmission = self.inputTransmission.value
            shouldOutput = true
        }
        
        if self.inputOcclusion.valueDidChange
        {
            self.material.occlusion = self.inputOcclusion.value
            shouldOutput = true
        }
        
        if self.inputThickness.valueDidChange
        {
            self.material.thickness = self.inputThickness.value
            shouldOutput = true
        }
        
        if self.inputIOR.valueDidChange
        {
            self.material.ior = self.inputIOR.value
            shouldOutput = true
        }
        
        
        if self.inputBumpTexture.valueDidChange
        {
            self.material.setTexture(self.inputBumpTexture.value?.texture, type: .bump)
            shouldOutput = true
        }
        
        if self.inputDisplacementTexture.valueDidChange
        {
            self.material.setTexture(self.inputDisplacementTexture.value?.texture, type: .displacement)
            shouldOutput = true
        }
        
        if self.inputOcclusionTexture.valueDidChange
        {
            self.material.setTexture(self.inputOcclusionTexture.value?.texture, type: .occlusion)
            shouldOutput = true
        }
        
        if self.inputSubsurfaceTexture.valueDidChange
        {
            self.material.setTexture(self.inputSubsurfaceTexture.value?.texture, type: .subsurface)
            shouldOutput = true
        }
        
        if self.inputClearcoatTexture.valueDidChange
        {
            self.material.setTexture(self.inputClearcoatTexture.value?.texture, type: .clearcoat)
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
        
        if self.inputTransmissionTexture.valueDidChange
        {
            self.material.setTexture(self.inputTransmissionTexture.value?.texture, type: .transmission)
            shouldOutput = true
        }
        
        return shouldOutput
    }
    
    override func execute(context:GraphExecutionContext,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
        let shoulOutput = self.evaluate(material: self.material, atTime: context.timing.time)

        if shoulOutput
        {
            self.outputMaterial.send(self.material)
        }
     }
}
