//
//  DepthMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//


import Foundation
import Satin
import simd
import Metal

public class DepthMaterialNode : BaseMaterialNode
{
    public override class var name:String {  "Depth Material" }

    public let inputNear:FloatParameter
    public let inputFar:FloatParameter
    public let inputInvert:BoolParameter
    public let inputColor:BoolParameter
    public override var inputParameters: [any Parameter] { super.inputParameters + [
        inputNear,
        inputFar,
        inputInvert,
        inputColor,
    ] }
    
    // Ports
    public let outputMaterial:NodePort<Material>
    public override var ports: [any NodePortProtocol] { super.ports + [ outputMaterial] }

    public override var material: DepthMaterial {
        return _material
    }
    
    private var _material = DepthMaterial()
    
    public required init(context:Context)
    {
        self.inputNear = FloatParameter("Near", 0.001, 0.0, 1000.0, .slider)
        self.inputFar = FloatParameter("Far", 10.0, 0.0, 1000.0, .slider)

        self.inputInvert = BoolParameter("Invert", false, .toggle)
        self.inputColor = BoolParameter("Color", true, .toggle)
        
        self.outputMaterial = NodePort<Material>(name: "Material", kind: .Outlet)

        super.init(context: context)
        
        self.material.near = 0.001
        self.material.far = 10.0
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputNearParameter
        case inputFarParameter
        case inputInvertParameter
        case inputColorParameter
        case outputMaterialPort
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputNear = try container.decode(FloatParameter.self, forKey: .inputNearParameter)
        self.inputFar = try container.decode(FloatParameter.self, forKey: .inputFarParameter)
        self.inputInvert = try container.decode(BoolParameter.self, forKey: .inputInvertParameter)
        self.inputColor = try container.decode(BoolParameter.self, forKey: .inputColorParameter)
        
        self.outputMaterial = try container.decode(NodePort<Material>.self, forKey: .outputMaterialPort)

        try super.init(from: decoder)
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputNear, forKey: .inputNearParameter)
        try container.encode(self.inputFar, forKey: .inputFarParameter)
        try container.encode(self.inputInvert, forKey: .inputInvertParameter)
        try container.encode(self.inputColor, forKey: .inputColorParameter)
        
        try container.encode(self.outputMaterial, forKey: .outputMaterialPort)

        try super.encode(to: encoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.evaluate(material: self.material, atTime: context.timing.time)
        
        self.material.far = self.inputFar.value
        self.material.near = self.inputNear.value
        self.material.invert = self.inputInvert.value
        self.material.color = self.inputColor.value
        
        self.outputMaterial.send(self.material)
    }
}
