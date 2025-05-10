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

    // Parameters
    let inputColor = Float4Parameter("Color", .one, .zero, .one, .colorpicker)
    
    override var inputParameters: [any Parameter] { super.inputParameters + [inputColor] }
    
    // Ports
    let outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)

    private let material = BasicColorMaterial()
    
    override var ports: [any AnyPort] { super.ports + [ outputMaterial] }
    
    required init(context:Context)
    {
        super.init(context: context)
        
        self.material.color = simd_float4(1.0, 0.0, 0.0, 1.0)
    }
    
    required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
    }
    
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.evaluate(material: self.material, atTime: atTime)
        
        self.material.color = self.inputColor.value
        
        self.outputMaterial.send(self.material)
     }
}
