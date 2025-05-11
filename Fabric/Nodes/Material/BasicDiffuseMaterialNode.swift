//
//  BasicDiffuseMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import Satin
import simd
import Metal

class BasicDiffuseMaterialNode : BaseMaterialNode, NodeProtocol
{
    static let name = "Diffuse Material"
    static var nodeType = Node.NodeType.Material

    // Ports
    let inputColor = NodePort<simd_float4>(name: "Color", kind: .Inlet)
    let inputHardness = NodePort<Float>(name: "Hardness", kind: .Inlet)
    let outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)

    private let material = BasicDiffuseMaterial()
    
    override var ports: [any NodePortProtocol] {  super.ports + [ inputColor, inputHardness, outputMaterial] }
    
    required init(context:Context)
    {
        super.init(context: context)
        
        self.material.color = simd_float4(1.0, 1.0, 1.0, 1.0)
//        self.material. = 0.7
        
    }
    
    required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
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
        
//        if let tex = self.inputHardness.value
//        {
//            self.material.ha = tex
//        }
        
//        self.material.color = simd_float4( cosf(Float(atTime.remainder(dividingBy: 1) )  * Float.pi ) , 0.0, 0.0, 1.0)

        
        self.outputMaterial.send(self.material)
     }
}
