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

public class BaseMaterialNode : Node, NodeProtocol
{
    
    public class var name:String {  "Material" }
    public class var nodeType:Node.NodeType { .Material }

    // Ports
    public let outputMaterial:NodePort<Material>
    public override var ports: [any NodePortProtocol] { [ self.outputMaterial] + super.ports}
    
    // Params
    public let inputReceivesLighting:BoolParameter
    public let inputWriteDepth:BoolParameter
    public let inputBlending:StringParameter

    public override var inputParameters: [any Parameter] {
        [self.inputReceivesLighting,
         self.inputWriteDepth,
         self.inputBlending,
    ] + super.inputParameters}
    
    
    
    open var material: Material {
        fatalError("Subclasses must override material")
    }

    
    public required init(context: Context) {
        
        
        self.inputReceivesLighting = BoolParameter("Receives Lighting", true, .button)
        self.inputWriteDepth = BoolParameter("Write Depth", true, .button)
        self.inputBlending = StringParameter("Blending Mode", "Disabled", ["Disabled", "Alpha", "Additive", "Subtractive"], .dropdown)

        self.outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)

        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputReceivesLightingParam
        case inputWriteDepthParam
        case inputBlendingParam
        case outputMaterialPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputReceivesLighting, forKey: .inputReceivesLightingParam)
        try container.encode(self.inputWriteDepth, forKey: .inputWriteDepthParam)
        try container.encode(self.inputBlending, forKey: .inputBlendingParam)
        try container.encode(self.outputMaterial, forKey: .outputMaterialPort)

        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputReceivesLighting = try container.decode(BoolParameter.self, forKey: .inputReceivesLightingParam)
        self.inputWriteDepth = try container.decode(BoolParameter.self, forKey: .inputWriteDepthParam)
        
        self.inputBlending = try container.decode(StringParameter.self, forKey: .inputBlendingParam)
        
        self.inputBlending.options = ["Disabled", "Alpha", "Additive", "Subtractive"]
        
        self.outputMaterial = try container.decode(NodePort<Material>.self, forKey: .outputMaterialPort)

        try super.init(from: decoder)
    }
    
    public func evaluate(material:Material, atTime:TimeInterval)
    {
        material.blending = self.blendingMode()
        material.lighting = self.inputReceivesLighting.value
        material.depthWriteEnabled = self.inputWriteDepth.value
        material.depthCompareFunction = (self.inputWriteDepth.value) ? .greaterEqual : .always
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
