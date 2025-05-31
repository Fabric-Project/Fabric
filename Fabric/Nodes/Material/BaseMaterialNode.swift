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

class BaseMaterialNode : Node, NodeProtocol
{
    
    class var name:String {  "Material" }
    class var nodeType:Node.NodeType { .Material }

    // Params
    let inputReceivesLighting:BoolParameter
    let inputWriteDepth:BoolParameter
    let inputBlending:StringParameter

    override var inputParameters: [any Parameter] { super.inputParameters + [self.inputReceivesLighting,
                                                                              self.inputWriteDepth,
                                                                             self.inputBlending,
    ] }
    
    required init(context: Context) {
        
        self.inputReceivesLighting = BoolParameter("Receives Lighting", true, .button)
        self.inputWriteDepth = BoolParameter("Write Depth", true, .button)
        self.inputBlending = StringParameter("Blending Mode", "Disabled", ["Disabled", "Alpha", "Additive", "Subtractive"], .dropdown)

        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputReceivesLightingParam
        case inputWriteDepthParam
        case inputBlendingParam
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputReceivesLighting, forKey: .inputReceivesLightingParam)
        try container.encode(self.inputWriteDepth, forKey: .inputWriteDepthParam)
        try container.encode(self.inputBlending, forKey: .inputBlendingParam)

        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputReceivesLighting = try container.decode(BoolParameter.self, forKey: .inputReceivesLightingParam)
        self.inputWriteDepth = try container.decode(BoolParameter.self, forKey: .inputWriteDepthParam)
        
        self.inputBlending = try container.decode(StringParameter.self, forKey: .inputBlendingParam)
        
        self.inputBlending.options = ["Disabled", "Alpha", "Additive", "Subtractive"]
        
        try super.init(from: decoder)
    }
    
    func evaluate(material:Material, atTime:TimeInterval)
    {
        material.blending = self.blendingMode()
        material.lighting = self.inputReceivesLighting.value
        material.depthWriteEnabled = self.inputWriteDepth.value
    }
    
    private func blendingMode() -> Blending
    {
        switch self.inputBlending.value
        {
        case "Disabled":
            return .disabled
            
        case "Alpha":
            return .alpha

        case "Additive":
            return .additive
            
        case "Subtractive":
            return .subtract

        default: return .subtract
        }
    }
}
