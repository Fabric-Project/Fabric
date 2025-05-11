//
//  DepthMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//


import Foundation
import Satin
import simd
import Metal

class DepthMaterialNode : BaseMaterialNode, NodeProtocol
{
    static let name = "Depth Material"
    static var nodeType = Node.NodeType.Material

    // Ports
    let outputMaterial = NodePort<Material>(name: DepthMaterialNode.name , kind: .Outlet)

    private let material = DepthMaterial()
    
    override var ports: [any NodePortProtocol] {  super.ports + [outputMaterial] }
    
    required init(context:Context)
    {
        super.init(context: context)
        
        self.material.near = 2
        self.material.far = 7
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
