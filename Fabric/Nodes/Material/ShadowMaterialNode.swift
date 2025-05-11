//
//  ShadowMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/28/25.
//


import Foundation
import Satin
import simd
import Metal

class ShadowMaterialNode : BaseMaterialNode, NodeProtocol
{
    static let name = "Shadow Material"
    static var nodeType = Node.NodeType.Material

    // Ports
    let outputMaterial = NodePort<Material>(name: ShadowMaterialNode.name , kind: .Outlet)

    private let material = ShadowMaterial()
    
    override var ports: [any NodePortProtocol] {  super.ports + [outputMaterial] }
    
    required init(context:Context)
    {
        super.init(context: context)
        
    }
    
    required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
    }

    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.evaluate(material: self.material, atTime: atTime)

        self.outputMaterial.send(self.material)
     }
}
