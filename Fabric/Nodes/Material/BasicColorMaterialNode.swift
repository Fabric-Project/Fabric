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
    //    override static func foo() -> String  { "foo" }
    
    class var name:String {  "Color Material" }
    class var nodeType:Node.NodeType { .Material }
    
    // Parameters
    let inputColor:Float4Parameter
    override var inputParameters: [any Parameter] { super.inputParameters + [inputColor] }
    
    // Ports
    let outputMaterial:NodePort<Material>
    override var ports: [any NodePortProtocol] { super.ports + [ outputMaterial] }
    
    private let material = BasicColorMaterial()
    
    required init(context:Context)
    {
        self.inputColor = Float4Parameter("Color", .one, .zero, .one, .colorpicker)
        self.outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)
        
        super.init(context: context)
        
        self.material.color = simd_float4(1.0, 0.0, 0.0, 1.0)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputColorParameter
        case outputMaterialPort
    }
    
    required init(from decoder: any Decoder) throws {
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.inputColor = try container.decode(Float4Parameter.self, forKey: .inputColorParameter)
        
        self.outputMaterial = try container.decode(NodePort<Material>.self, forKey: .outputMaterialPort)
        
        try super.init(from: decoder)
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputColor, forKey: .inputColorParameter)
        try container.encode(self.outputMaterial, forKey: .outputMaterialPort)
        
        try super.encode(to: encoder)
    }
    
    override func evaluate(material:Material, atTime:TimeInterval)
    {
        super.evaluate(material: material, atTime: atTime)
        self.material.color = self.inputColor.value
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.evaluate(material: self.material, atTime: atTime)
        
        self.outputMaterial.send(self.material)
    }
}
