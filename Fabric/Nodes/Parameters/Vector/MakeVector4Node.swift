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

public class MakeVector4Node : Node, NodeProtocol
{
    public static let name = "Vector 4"
    public static var nodeType = Node.NodeType.Parameter(parameterType: .Vector)

    // Params
    public let inputXParam:FloatParameter
    public let inputYParam:FloatParameter
    public let inputZParam:FloatParameter
    public let inputWParam:FloatParameter

    public override var inputParameters: [any Parameter] {  [inputXParam, inputYParam, inputZParam, inputWParam] + super.inputParameters}

    // Ports
    public let outputVector:NodePort<simd_float4>
    public override var ports: [any NodePortProtocol] { [outputVector] + super.ports }
    
    private var vector = simd_float4(repeating: 0)

    public required init(context: Context)
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
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputXParam, forKey: .inputXParameter)
        try container.encode(self.inputYParam, forKey: .inputYParameter)
        try container.encode(self.inputZParam, forKey: .inputZParameter)
        try container.encode(self.inputWParam, forKey: .inputWParameter)
        try container.encode(self.outputVector, forKey: .outputVectorPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputXParam = try container.decode(FloatParameter.self, forKey: .inputXParameter)
        self.inputYParam = try container.decode(FloatParameter.self, forKey: .inputYParameter)
        self.inputZParam = try container.decode(FloatParameter.self, forKey: .inputZParameter)
        self.inputWParam = try container.decode(FloatParameter.self, forKey: .inputWParameter)
        self.outputVector = try container.decode(NodePort<simd_float4>.self, forKey: .outputVectorPort)
        
        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputXParam.valueDidChange || self.inputYParam.valueDidChange || self.inputZParam.valueDidChange || self.inputWParam.valueDidChange
        {
            self.vector = simd_float4(inputXParam.value,
                                      inputYParam.value,
                                      inputZParam.value,
                                      inputWParam.value)
            
            self.outputVector.send( self.vector )
        }
    }
}
