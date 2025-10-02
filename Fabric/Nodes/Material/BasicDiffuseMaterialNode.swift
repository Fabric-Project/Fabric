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

public class BasicDiffuseMaterialNode : BasicColorMaterialNode
{
    
    public override class var name:String {  "Diffuse Material" }

    public let inputHardness:FloatParameter
    public override var inputParameters:[any Parameter] { [inputHardness] + super.inputParameters }
    
    public override var material: BasicDiffuseMaterial {
        return _material
    }
    
    private var _material = BasicDiffuseMaterial()
    
    public required init(context:Context)
    {
        self.inputHardness = FloatParameter("Hardness", 1, 0, 1, .slider)

        super.init(context: context)
    }

    enum CodingKeys : String, CodingKey
    {
        case inputHardnessParameter
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.inputHardness = try container.decode(FloatParameter.self, forKey: .inputHardnessParameter)
        try super.init(from: decoder)
    }
    
    public override func encode(to encoder: any Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.inputHardness, forKey: .inputHardnessParameter)
        try super.encode(to: encoder)
    }
    
    public override func evaluate(material:Material, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)
        
        if self.inputHardness.valueDidChange
        {
            self.material.hardness = self.inputHardness.value
            shouldOutput = true
        }
        
        return shouldOutput
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let shouldOutput = self.evaluate(material: self.material, atTime: context.timing.time)
        
        if shouldOutput
        {
            self.outputMaterial.send(self.material)
        }
    }
}
