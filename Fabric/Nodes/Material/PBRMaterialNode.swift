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

class PBRMaterialNode : BaseMaterialNode, NodeProtocol
{
    static let name = "Physical Material"
    static var nodeType = Node.NodeType.Material

    // Params
    let inputBaseColor = GenericParameter<simd_float4>("Base Color", simd_float4(repeating:1), .colorpicker)
    
    let inputMetallic = FloatParameter("Metallic", 0.75, 0.0, 1.0, .slider)
    let inputSpecular = FloatParameter("Specular", 0.25, 0.0, 1.0, .slider)
    let inputRoughness = FloatParameter("Roughness", 0.25, 0.0, 1.0, .slider)
    let inputEmissiveColor = Float4Parameter("Emissive Color", simd_float4(repeating:0), .colorpicker)
    let inputSubsurface = FloatParameter("Sub Surface", 0.0, 0.0, 1.0, .slider)
    let inputAnisotropic = FloatParameter("Anisotropic", 0.0, 0.0, 1.0, .slider)
    let inputAnisotropicAngle = FloatParameter("Anisotropic Angle", 0.0, 0.0, 1.0, .slider)
    let inputSpecularTint = FloatParameter("Specular Tint", 0.0, 0.0, 1.0, .slider)
    let inputClearcoat = FloatParameter("Clearcoat", 0.0, 0.0, 1.0, .slider)
    let inputClearcoatRoughness = FloatParameter("Clearcoat Roughness", 0.0, 0.0, 1.0, .slider)
    let inputSheen = FloatParameter("Sheen", 0.0, 0.0, 1.0, .slider)
    let inputSheenTint = FloatParameter("Sheen Tint", 0.0, 0.0, 1.0, .slider)
    let inputTransmission = FloatParameter("Transmission", 0.0, 0.0, 1.0, .slider)
    let inputOcclusion = FloatParameter("Occlusion", 1.0, 0.0, 1.0, .slider)
    let inputThickness = FloatParameter("Thickness", 1.0, 0.0, 1.0, .slider)
    let inputIOR = FloatParameter("Index of Refraction", 1.5, 0.0, 10.0, .slider)

    override var inputParameters: [any Parameter] { super.inputParameters +
        [
            inputMetallic,
            inputSpecular,
            inputRoughness,
            inputEmissiveColor,
            inputSubsurface,
            inputAnisotropic,
            inputAnisotropicAngle,
            inputSpecularTint,
            inputClearcoat,
            inputClearcoatRoughness,
            inputSheen,
            inputSheenTint,
            inputTransmission,
            inputOcclusion,
            inputThickness,
            inputIOR,
        ] }

    // Ports
    let inputDiffuseTexture = NodePort<EquatableTexture>(name: "Diffuse Texture", kind: .Inlet)
    let inputNormalTexture = NodePort<EquatableTexture>(name: "Normal Texture", kind: .Inlet)
    let outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)

    private let material = PhysicalMaterial()
    
    override var ports: [any NodePortProtocol] {  super.ports + [ inputDiffuseTexture,
                                                         inputNormalTexture,
                                                         outputMaterial] }
    
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
        self.evaluate(material: self.material, atTime: atTime)

//        self.material.baseColor = self.inputBaseColor.value
//        self.material.emissiveColor = self.inputEmissiveColor.value
//        
//        self.material.specular = self.inputSpecular.value
//        self.material.metallic = self.inputMetallic.value
//        self.material.roughness = self.inputRoughness.value
//        self.material.occlusion = self.inputOcclusion.value
       
        
        self.material.metallic = self.inputMetallic.value
        self.material.specular = self.inputSpecular.value
        self.material.roughness = self.inputRoughness.value
        self.material.emissiveColor = self.inputEmissiveColor.value
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
        
        if let tex = self.inputDiffuseTexture.value
        {
            self.material.setTexture(tex.texture, type: .baseColor)
        }
        
        if let tex = self.inputNormalTexture.value
        {
            self.material.setTexture(tex.texture, type: .normal)
        }
        
//        if let tex = self.inputHardness.value
//        {
//            self.material.ha = tex
//        }
        
//        self.material.color = simd_float4( cosf(Float(atTime.remainder(dividingBy: 1) )  * Float.pi ) , 0.0, 0.0, 1.0)

        
        self.outputMaterial.send(self.material)
     }
}
