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

public class MakeVector2Node : Node
{
    override public static var name:String { "Vector 2" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }

    // Params
    public let inputXParam:FloatParameter
    public let inputYParam:FloatParameter
    public override var inputParameters: [any Parameter] { [inputXParam, inputYParam] + super.inputParameters}
    
    // Ports
    public let outputVector:NodePort<simd_float2>
    public override var ports: [Port] { [outputVector] + super.ports}

    private var vector = simd_float2(repeating: 0)

    public required init(context: Context)
    {
        self.inputXParam = FloatParameter("X", 0.0, .inputfield)
        self.inputYParam = FloatParameter("Y", 0.0, .inputfield)
        self.outputVector = NodePort<simd_float2>(name: "Vector 2" , kind: .Outlet)
        
        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputXParameter
        case inputYParameter
        case outputVectorPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputXParam, forKey: .inputXParameter)
        try container.encode(self.inputYParam, forKey: .inputYParameter)
        try container.encode(self.outputVector, forKey: .outputVectorPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputXParam = try container.decode(FloatParameter.self, forKey: .inputXParameter)
        self.inputYParam = try container.decode(FloatParameter.self, forKey: .inputYParameter)
        self.outputVector = try container.decode(NodePort<simd_float2>.self, forKey: .outputVectorPort)
        
        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputXParam.valueDidChange || self.inputYParam.valueDidChange
        {
            self.vector = simd_float2(inputXParam.value,
                                      inputYParam.value)
            
            self.outputVector.send( self.vector )
        }
     }
}
