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

    // Ports
    let inputDiffuseTexture = NodePort<(any MTLTexture)>(name: "Diffuse Texture", kind: .Inlet)
    let inputNormalTexture = NodePort<(any MTLTexture)>(name: "Diffuse Texture", kind: .Inlet)
    let inputColor = NodePort<simd_float4>(name: "Color", kind: .Inlet)
    let inputHardness = NodePort<Float>(name: "Hardness", kind: .Inlet)
    let outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)

    private let material = StandardMaterial()
    
    override var ports: [any AnyPort] {  super.ports + [ inputDiffuseTexture,
                                                         inputNormalTexture,
                                                         inputColor,
                                                         inputHardness,
                                                         outputMaterial] }
    
    required init(context:Context)
    {
        super.init(context: context)
        
        self.material.baseColor = simd_float4(1.0, 1.0, 1.0, 1.0)
        self.material.metallic = 0.75
        self.material.roughness = 0.25
//        self.material. = 0.7
        
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        
        self.evaluate(material: self.material, atTime: atTime)

        if let color = self.inputColor.value
        {
            self.material.baseColor = color
        }
        
        if let tex = self.inputDiffuseTexture.value
        {
            self.material.setTexture(tex, type: .baseColor)
        }
        
        if let tex = self.inputNormalTexture.value
        {
            self.material.setTexture(tex, type: .normal)
        }
        
//        if let tex = self.inputHardness.value
//        {
//            self.material.ha = tex
//        }
        
//        self.material.color = simd_float4( cosf(Float(atTime.remainder(dividingBy: 1) )  * Float.pi ) , 0.0, 0.0, 1.0)

        
        self.outputMaterial.send(self.material)
     }
}
