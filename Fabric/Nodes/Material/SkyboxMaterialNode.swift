//
//  SkyboxMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//



import Foundation
import Satin
import simd
import Metal

class SkyboxMaterialNode : Node, NodeProtocol
{
    static let name = "Skybox Material"
    static var type = Node.NodeType.Material

    // Ports
    let inputTexture = NodePort<MTLTexture>(name: "Texture", kind: .Inlet)

    let outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)

    private let material = SkyboxMaterial()
    
    override var ports: [any AnyPort] { [inputTexture, outputMaterial] }
    
    required init(context:Context)
    {
        super.init(context: context, type: .Material, name: SkyboxMaterialNode.name)
        
        self.material.setup()
        
        self.material.color = simd_float4(1.0, 0.0, 0.0, 1.0)
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
       
        
//        self.material.color = simd_float4( cosf(Float(atTime.remainder(dividingBy: 1) )  * Float.pi ) , 0.0, 0.0, 1.0)

        
        self.outputMaterial.send(self.material)
     }
}
