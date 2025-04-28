//
//  BasicColorMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//

import Foundation
import Satin
import simd
import Metal

class BasicColorMaterialNode : BaseMaterialNode, NodeProtocol
{
  
    static let name = "Color Material"
    static var nodeType = Node.NodeType.Material

    // Ports
    let inputColor = NodePort<simd_float4>(name: "Color", kind: .Inlet)
    let outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)

    private let material = BasicColorMaterial()
    
    override var ports: [any AnyPort] { super.ports + [inputColor, outputMaterial] }
    
    required init(context:Context)
    {
        super.init(context: context)
        
        self.material.color = simd_float4(1.0, 0.0, 0.0, 1.0)
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
        
        
        self.outputMaterial.send(self.material)
     }
}
