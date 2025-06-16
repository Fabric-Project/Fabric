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

// Not sure we need this node TBH?
// Its disabled in registry for now
// And needs codable additions
class ShadowMaterialNode : BaseMaterialNode
{
    override class var name:String {  "Shadow Material" }

    // Ports
    let outputMaterial = NodePort<Material>(name: ShadowMaterialNode.name , kind: .Outlet)
    
    override var ports: [any NodePortProtocol] {  super.ports + [outputMaterial] }

    override var material: ShadowMaterial {
        return _material
    }
    
    private var _material = ShadowMaterial()
    
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
