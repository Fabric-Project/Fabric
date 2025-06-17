//
//  BasicDiffuseMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import Satin
import simd
import Metal

class BasicDiffuseMaterialNode : BasicColorMaterialNode
{
    
    override class var name:String {  "Diffuse Material" }

    let inputHardness:FloatParameter
    override var inputParameters:[any Parameter] { [inputHardness] + super.inputParameters }
    
    override var material: BasicDiffuseMaterial {
        return _material
    }
    
    private var _material = BasicDiffuseMaterial()
    
    required init(context:Context)
    {
        self.inputHardness = FloatParameter("Hardness", 1, 0, 1, .slider)

        super.init(context: context)
    }

    enum CodingKeys : String, CodingKey
    {
        case inputHardnessParameter
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.inputHardness = try container.decode(FloatParameter.self, forKey: .inputHardnessParameter)
        try super.init(from: decoder)
    }
    
    override func encode(to encoder: any Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.inputHardness, forKey: .inputHardnessParameter)
        try super.encode(to: encoder)
    }
    
    override func evaluate(material:Material, atTime:TimeInterval)
    {
        super.evaluate(material: material, atTime: atTime)
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.evaluate(material: self.material, atTime: atTime)
        self.material.hardness = self.inputHardness.value

        self.outputMaterial.send(self.material)
    }
}
