//
//  MakeVector4Node.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import Satin
import simd
import Metal

class MakeVector4Node : Node, NodeProtocol
{
    static let name = "Vector 4"
    static var nodeType = Node.NodeType.Parameter(parameterType: .Vector)

    // Params
    let inputXParam:FloatParameter
    let inputYParam:FloatParameter
    let inputZParam:FloatParameter
    let inputWParam:FloatParameter

    override var inputParameters: [any Parameter] {  [inputXParam, inputYParam, inputZParam, inputWParam]}

    // Ports
    let outputVector:NodePort<simd_float4>
    override var ports: [any NodePortProtocol] { super.ports + [outputVector] }
    
    private var vector = simd_float4(repeating: 0)

    required init(context: Context)
    {
        self.inputXParam = FloatParameter("X", 0.0, .inputfield)
        self.inputYParam = FloatParameter("Y", 0.0, .inputfield)
        self.inputZParam = FloatParameter("Z", 0.0, .inputfield)
        self.inputWParam = FloatParameter("W", 0.0, .inputfield)
        self.outputVector = NodePort<simd_float4>(name: "Vector 4" , kind: .Outlet)
        
        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputXParameter
        case inputYParameter
        case inputZParameter
        case inputWParameter
        case outputVectorPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputXParam, forKey: .inputXParameter)
        try container.encode(self.inputYParam, forKey: .inputYParameter)
        try container.encode(self.inputZParam, forKey: .inputZParameter)
        try container.encode(self.inputWParam, forKey: .inputWParameter)
        try container.encode(self.outputVector, forKey: .outputVectorPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputXParam = try container.decode(FloatParameter.self, forKey: .inputXParameter)
        self.inputYParam = try container.decode(FloatParameter.self, forKey: .inputYParameter)
        self.inputZParam = try container.decode(FloatParameter.self, forKey: .inputZParameter)
        self.inputWParam = try container.decode(FloatParameter.self, forKey: .inputWParameter)
        self.outputVector = try container.decode(NodePort<simd_float4>.self, forKey: .outputVectorPort)
        
        try super.init(from: decoder)
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.vector = simd_float4(inputXParam.value,
                                  inputYParam.value,
                                  inputZParam.value,
                                  inputWParam.value)

        self.outputVector.send( self.vector )
     }
}
