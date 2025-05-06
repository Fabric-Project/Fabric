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

class SkyboxMaterialNode : BaseMaterialNode, NodeProtocol
{
    static let name = "Skybox Material"
    static var nodeType = Node.NodeType.Material

    // Ports
    let inputTexture = NodePort<EquatableTexture>(name: "Texture", kind: .Inlet)

    let outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)

    private let material = SkyboxMaterial()
    
    override var ports: [any AnyPort] {  super.ports + [inputTexture, outputMaterial] }
    
    required init(context:Context)
    {
        super.init(context: context)
        
        self.material.setup()
        
//        self.material.color = simd_float4(1.0, 0.0, 0.0, 1.0)
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
       
        self.evaluate(material: self.material, atTime: atTime)

        
        self.outputMaterial.send(self.material)
     }
}
