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

class DepthMaterialNode : Node
{
    // Ports
//    let inputColor = NodePort<simd_float4>(name: "Color", kind: .Inlet)
    let outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)

    private let material = DepthMaterial()
    
    override var ports: [any AnyPort] { [outputMaterial] }
    
    required init(context:Context)
    {
        super.init(context: context, type: .Material, name:"Depth Material")
        
        self.material.near = 2
        self.material.far = 7
        
//        self.material.color = simd_float4(1.0, 0.0, 0.0, 1.0)
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
//        if let color = self.inputColor.value
//        {
//            self.material.color = color
//        }
//        
//        self.material.color = simd_float4( cosf(Float(atTime.remainder(dividingBy: 1) )  * Float.pi ) , 0.0, 0.0, 1.0)

        
        self.outputMaterial.send(self.material)
     }
}
