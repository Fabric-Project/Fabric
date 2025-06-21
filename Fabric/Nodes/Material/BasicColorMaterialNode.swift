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

public class BasicColorMaterialNode : BaseMaterialNode
{
    public override class var name:String {  "Color Material" }
    
    // Parameters
    public let inputColor:Float4Parameter
    public override var inputParameters: [any Parameter] { super.inputParameters + [inputColor] }
    
    // Ports
    public let outputMaterial:NodePort<Material>
    public override var ports: [any NodePortProtocol] { super.ports + [ outputMaterial] }
    
    public override var material: BasicColorMaterial {
        return _material
    }
    
    private var _material = BasicColorMaterial()

    public required init(context:Context)
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
    
    public required init(from decoder: any Decoder) throws {
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.inputColor = try container.decode(Float4Parameter.self, forKey: .inputColorParameter)
        
        self.outputMaterial = try container.decode(NodePort<Material>.self, forKey: .outputMaterialPort)
        
        try super.init(from: decoder)
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputColor, forKey: .inputColorParameter)
        try container.encode(self.outputMaterial, forKey: .outputMaterialPort)
        
        try super.encode(to: encoder)
    }
    
    public override func evaluate(material:Material, atTime:TimeInterval)
    {
        super.evaluate(material: material, atTime: atTime)
        self.material.color = self.inputColor.value
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.evaluate(material: self.material, atTime: context.timing.time)
        
        self.outputMaterial.send(self.material)
    }
}
