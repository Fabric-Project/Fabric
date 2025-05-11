//
//  BaseMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import Satin
import simd
import Metal

class BaseMaterialNode : Node
{
    // Params
    let inputReceivesLighting:BoolParameter
    let inputWriteDepth:BoolParameter
    
    override var inputParameters: [any Parameter] { super.inputParameters + [ self.inputReceivesLighting,
                                                                              self.inputWriteDepth, ] }
    
    required init(context: Context) {
        
        self.inputReceivesLighting = BoolParameter("Receives Lighting", true, .button)
        self.inputWriteDepth = BoolParameter("Write Depth", true, .button)
        
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputReceivesLightingParam
        case inputWriteDepthParam
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputReceivesLighting, forKey: .inputReceivesLightingParam)
        try container.encode(self.inputWriteDepth, forKey: .inputWriteDepthParam)

        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputReceivesLighting = try container.decode(BoolParameter.self, forKey: .inputReceivesLightingParam)
        self.inputWriteDepth = try container.decode(BoolParameter.self, forKey: .inputWriteDepthParam)
        
        try super.init(from: decoder)
    }
    
    func evaluate(material:Material, atTime:TimeInterval)
    {
        material.lighting = self.inputReceivesLighting.value
        material.depthWriteEnabled = self.inputWriteDepth.value
    }
    
   
}
