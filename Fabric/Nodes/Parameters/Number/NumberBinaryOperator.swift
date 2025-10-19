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

public class NumberBinaryOperator : Node
{
    override public static var name:String { "Number Binary Operator" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }

    // Params
    public let inputAParam:FloatParameter
    public let inputBParam:FloatParameter
    public let inputOperatorParam:StringParameter
    public override var inputParameters:[any Parameter] {  [inputAParam, inputBParam, inputOperatorParam] + super.inputParameters}

    // Ports
    public let outputNumber:NodePort<Float>
    private var mathOperator = BinaryMathOperator.Add
    private var output:Float = 0.0
    
    public override var ports: [Port] { [outputNumber] + super.ports }

    public required init(context: Context)
    {
        self.inputAParam = FloatParameter("A", 0.0, .inputfield)
        self.inputBParam = FloatParameter("B", 0.0, .inputfield)
        self.inputOperatorParam = StringParameter("Operator", "Add", BinaryMathOperator.allCases.map(\.rawValue))
        
        self.outputNumber = NodePort<Float>(name: "Result" , kind: .Outlet)
        
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
        try container.encode(self.inputBParam, forKey: .inputBParameter)
        try container.encode(self.inputOperatorParam, forKey: .inputOperatorParameter)
        try container.encode(self.outputNumber, forKey: .outputNumberPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputAParam = try container.decode(FloatParameter.self, forKey: .inputAParameter)
        self.inputBParam = try container.decode(FloatParameter.self, forKey: .inputBParameter)
        
        self.inputOperatorParam = try container.decode(StringParameter.self, forKey: .inputOperatorParameter)
        self.inputOperatorParam.options = BinaryMathOperator.allCases.map(\.rawValue)
        
        self.outputNumber = try container.decode(NodePort<Float>.self, forKey: .outputNumberPort)
        
        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputOperatorParam.valueDidChange,
           let mathOp = BinaryMathOperator(rawValue: self.inputOperatorParam.value)
        {
            self.mathOperator = mathOp
        }
        
        if self.inputOperatorParam.valueDidChange || self.inputAParam.valueDidChange || self.inputBParam.valueDidChange
        {
            self.output = self.mathOperator.perform(lhs: self.inputAParam.value,
                                                    rhs: self.inputBParam.value)
        }
        
        self.outputNumber.send(self.output)
    }
}
