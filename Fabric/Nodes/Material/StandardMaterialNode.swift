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

class StandardMaterialNode : BaseMaterialNode, NodeProtocol
{
    static let name = "Standard Material"
    static var nodeType = Node.NodeType.Material

    // Params
    let inputBaseColor = GenericParameter<simd_float4>("Base Color", simd_float4(repeating:1), .colorpicker)
    let inputEmissiveColor = GenericParameter<simd_float4>("Emissive Color", simd_float4(repeating:0), .colorpicker)
    
    //Float4Parameter("Base Color", simd_float4(repeating: 1), simd_float4(repeating: 0), simd_float4(repeating: 1), .slider)
    //let inputEmissiveColor = Float4Parameter("Emissive Color", simd_float4(repeating: 0), simd_float4(repeating: 0), simd_float4(repeating: 1), .slider)

    let inputSpecular = FloatParameter("Specular", 0.25, 0.0, 1.0, .slider)
    let inputRoughness = FloatParameter("Roughness", 0.25, 0.0, 1.0, .slider)
    let inputMetallic = FloatParameter("Metallic", 0.75, 0.0, 1.0, .slider)
    let inputOcclusion = FloatParameter("Occlusion", 0.75, 0.0, 1.0, .slider)

    override var inputParameters: [any Parameter] { super.inputParameters + [inputBaseColor, inputEmissiveColor, inputSpecular, inputMetallic, inputRoughness, inputOcclusion, ] }

    // Ports
    let inputDiffuseTexture = NodePort<EquatableTexture>(name: "Diffuse Texture", kind: .Inlet)
    let inputNormalTexture = NodePort<EquatableTexture>(name: "Normal Texture", kind: .Inlet)
    let outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)

    private let material = StandardMaterial()
    
    override var ports: [any AnyPort] {  super.ports + [ inputDiffuseTexture,
                                                         inputNormalTexture,
                                                         outputMaterial] }
    
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
        self.evaluate(material: self.material, atTime: atTime)

        self.material.baseColor = self.inputBaseColor.value
        self.material.emissiveColor = self.inputEmissiveColor.value
        
        self.material.specular = self.inputSpecular.value
        self.material.metallic = self.inputMetallic.value
        self.material.roughness = self.inputRoughness.value
        self.material.occlusion = self.inputOcclusion.value
        
        
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
