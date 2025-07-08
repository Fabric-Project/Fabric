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
    
    override  func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        self.evaluate(material: self.material, atTime: context.timing.time)
        
        self.outputMaterial.send(self.material)
    }
}
