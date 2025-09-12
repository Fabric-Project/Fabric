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
    override class var name:String {  "Physical Material" }

    // Params
    let inputSubsurface = FloatParameter("Sub Surface", 0.0, 0.0, 1.0, .slider)
    let inputAnisotropic = FloatParameter("Anisotropic", 0.0, 0.0, 1.0, .slider)
    let inputAnisotropicAngle = FloatParameter("Anisotropic Angle", 0.0, 0.0, 1.0, .slider)
    let inputSpecularTint = FloatParameter("Specular Tint", 0.0, 0.0, 1.0, .slider)
    let inputClearcoat = FloatParameter("Clearcoat", 0.0, 0.0, 1.0, .slider)
    let inputClearcoatRoughness = FloatParameter("Clearcoat Roughness", 0.0, 0.0, 1.0, .slider)
    let inputSheen = FloatParameter("Sheen", 0.0, 0.0, 1.0, .slider)
    let inputSheenTint = FloatParameter("Sheen Tint", 0.0, 0.0, 1.0, .slider)
    let inputTransmission = FloatParameter("Transmission", 0.0, 0.0, 1.0, .slider)
    let inputThickness = FloatParameter("Thickness", 1.0, 0.0, 1.0, .slider)
    let inputIOR = FloatParameter("Index of Refraction", 1.5, 0.0, 10.0, .slider)

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

    override  func execute(context:GraphExecutionContext,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
        self.evaluate(material: self.material, atTime: context.timing.time)

        self.material.baseColor = self.inputBaseColor.value
        self.material.emissiveColor = self.inputEmissiveColor.value
        
        self.material.specular = self.inputSpecular.value
        self.material.metallic = self.inputMetallic.value
        self.material.roughness = self.inputRoughness.value
        self.material.occlusion = self.inputOcclusion.value
        self.material.environmentIntensity = self.inputEnvironmentIntensity.value
        self.material.gammaCorrection = self.inputGammaCorrection.value

        self.material.setTexture(self.inputDiffuseTexture.value?.texture, type: .baseColor)
        self.material.setTexture(self.inputNormalTexture.value?.texture, type: .normal)
        self.material.setTexture(self.inputEmissiveTexture.value?.texture, type: .emissive)
        self.material.setTexture(self.inputSpecularTexture.value?.texture, type: .specular)
        self.material.setTexture(self.inputRoughnessTexture.value?.texture, type: .roughness)
        self.material.setTexture(self.inputMetalicTexture.value?.texture, type: .metallic)
                
        self.material.subsurface = self.inputSubsurface.value
        self.material.anisotropic = self.inputAnisotropic.value
        self.material.anisotropicAngle = self.inputAnisotropicAngle.value
        self.material.specularTint = self.inputSpecularTint.value
        self.material.clearcoat = self.inputClearcoat.value
        self.material.clearcoatRoughness = self.inputClearcoatRoughness.value
        self.material.sheen = self.inputSheen.value
        self.material.sheenTint = self.inputSheenTint.value
        self.material.transmission = self.inputTransmission.value
        self.material.occlusion = self.inputOcclusion.value
        self.material.thickness = self.inputThickness.value
        self.material.ior = self.inputIOR.value
        
        self.material.setTexture(self.inputDiffuseTexture.value?.texture, type: .baseColor)
        self.material.setTexture(self.inputNormalTexture.value?.texture, type: .normal)
        self.material.setTexture(self.inputEmissiveTexture.value?.texture, type: .emissive)
        self.material.setTexture(self.inputSpecularTexture.value?.texture, type: .specular)
        self.material.setTexture(self.inputRoughnessTexture.value?.texture, type: .roughness)
        self.material.setTexture(self.inputMetalicTexture.value?.texture, type: .metallic)

        self.material.setTexture(self.inputBumpTexture.value?.texture, type: .bump)
        self.material.setTexture(self.inputDisplacementTexture.value?.texture, type: .displacement)
        self.material.setTexture(self.inputOcclusionTexture.value?.texture, type: .occlusion)
        self.material.setTexture(self.inputSubsurfaceTexture.value?.texture, type: .subsurface)
        self.material.setTexture(self.inputClearcoatTexture.value?.texture, type: .clearcoat)
        self.material.setTexture(self.inputClearcoatRoughTexture.value?.texture, type: .clearcoatRoughness)
        self.material.setTexture(self.inputClearcoatGlossTexture.value?.texture, type: .clearcoatGloss)
        self.material.setTexture(self.inputTransmissionTexture.value?.texture, type: .transmission)

        
//        if let tex = self.inputHardness.value
//        {
//            self.material.ha = tex
//        }
        
//        self.material.color = simd_float4( cosf(Float(atTime.remainder(dividingBy: 1) )  * Float.pi ) , 0.0, 0.0, 1.0)

        
        self.outputMaterial.send(self.material)
     }
}
