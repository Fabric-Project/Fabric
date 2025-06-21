//
//  FloatAddNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/2/25.
//

import Foundation


import Foundation
import Satin
import simd
import Metal

public class NumberUnnaryOperator : Node, NodeProtocol
{
    public static let name = "Number Unnary Operator"
    public static var nodeType = Node.NodeType.Parameter(parameterType: .Number)

    // Params
    public let inputAParam:FloatParameter
    public let inputOperatorParam:StringParameter
    public override var inputParameters:[any Parameter] { super.inputParameters + [inputAParam, inputOperatorParam] }

    // Ports
    public let outputNumber:NodePort<Float>
    public override var ports: [any NodePortProtocol] { super.ports + [ outputNumber] }

    private var mathOperator = UnaryMathOperator.Sine

    public required init(context: Context)
    {
        self.inputAParam = FloatParameter("A", 0.0, .inputfield)
        self.inputOperatorParam = StringParameter("Operator", "Sine", UnaryMathOperator.allCases.map(\.rawValue))
        
        self.outputNumber = NodePort<Float>(name: NumberUnnaryOperator.name , kind: .Outlet)
        
        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputAParameter
        case inputBParameter
        case inputOperatorParameter
        case outputNumberPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputAParam, forKey: .inputAParameter)
        try container.encode(self.inputOperatorParam, forKey: .inputOperatorParameter)
        try container.encode(self.outputNumber, forKey: .outputNumberPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputAParam = try container.decode(FloatParameter.self, forKey: .inputAParameter)
        self.inputOperatorParam = try container.decode(StringParameter.self, forKey: .inputOperatorParameter)
        
        self.outputNumber = try container.decode(NodePort<Float>.self, forKey: .outputNumberPort)
        
        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if let mathOp = UnaryMathOperator(rawValue: self.inputOperatorParam.value)
        {
            self.mathOperator = mathOp
        }
        
        self.outputNumber.send( self.mathOperator.perform(self.inputAParam.value) )
    }
}
