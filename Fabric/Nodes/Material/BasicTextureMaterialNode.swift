//
//  BasicTextureMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//


import Foundation
import Satin
import simd
import Metal

class BasicTextureMaterialNode : BaseMaterialNode, NodeProtocol
{
    static let name = "Texture Material"
    static var nodeType = Node.NodeType.Material

    // Ports
    let inputTexture = NodePort<EquatableTexture>(name: "Texture", kind: .Inlet)
    let inputColor = NodePort<simd_float4>(name: "Color", kind: .Inlet)
    let outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)

    private let material = BasicTextureMaterial()
    
    override var ports: [any NodePortProtocol] {  super.ports + [inputTexture, inputColor, outputMaterial] }
    
    required init(context:Context)
    {
        super.init(context: context)
        
        self.material.flipped = true
        self.material.color = simd_float4(1.0, 1.0, 1.0, 1.0)
        
    }
    
    required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)

        self.material.flipped = true
        self.material.color = simd_float4(1.0, 1.0, 1.0, 1.0)
    }

    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.evaluate(material: self.material, atTime: atTime)

        if let color = self.inputColor.value
        {
            self.material.color = color
        }
        
        if let tex = self.inputTexture.value
        {
            self.material.texture = tex.texture
        }
        
//        self.material.color = simd_float4( cosf(Float(atTime.remainder(dividingBy: 1) )  * Float.pi ) , 0.0, 0.0, 1.0)

        
        self.outputMaterial.send(self.material)
     }
}
