//
//  NumberNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/2/25.
//

import Foundation
import Satin
import simd
import Metal

public class NumberNode : Node, NodeProtocol
{
    public static let name = "Number"
    public static var nodeType = Node.NodeType.Parameter(parameterType: .Number)

    // Params
    public let inputNumberParam:FloatParameter

    public override var inputParameters:[any Parameter]  { super .inputParameters + [inputNumberParam] }

    // Ports
    public let outputNumber:NodePort<Float>
    public override var ports: [any NodePortProtocol] { super.ports + [ outputNumber] }

    public required init(context: Context)
    {
        self.inputNumberParam = FloatParameter("Number", 0.0, .inputfield)
        self.outputNumber = NodePort<Float>(name: NumberNode.name , kind: .Outlet)
        
        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputNumberParameter
        case outputNumberPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputNumberParam, forKey: .inputNumberParameter)
        try container.encode(self.outputNumber, forKey: .outputNumberPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputNumberParam = try container.decode(FloatParameter.self, forKey: .inputNumberParameter)
        self.outputNumber = try container.decode(NodePort<Float>.self, forKey: .outputNumberPort)
        
        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.outputNumber.send(self.inputNumberParam.value)
    }
}
