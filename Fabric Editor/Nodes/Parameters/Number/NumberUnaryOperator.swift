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

class NumberUnnaryOperator : Node, NodeProtocol
{
    static let name = "Number Unnary Operator"
    static var nodeType = Node.NodeType.Parameter(parameterType: .Number)

    // Params
    let inputAParam:FloatParameter
    let inputOperatorParam:StringParameter
    override var inputParameters:[any Parameter] { super.inputParameters + [inputAParam, inputOperatorParam] }

    // Ports
    let outputNumber:NodePort<Float>
    var mathOperator = UnaryMathOperator.Sine
    
    
    override var ports: [any NodePortProtocol] { super.ports + [ outputNumber] }

    required init(context: Context)
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
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputAParam, forKey: .inputAParameter)
        try container.encode(self.inputOperatorParam, forKey: .inputOperatorParameter)
        try container.encode(self.outputNumber, forKey: .outputNumberPort)
        
        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputAParam = try container.decode(FloatParameter.self, forKey: .inputAParameter)
        self.inputOperatorParam = try container.decode(StringParameter.self, forKey: .inputOperatorParameter)
        
        self.outputNumber = try container.decode(NodePort<Float>.self, forKey: .outputNumberPort)
        
        try super.init(from: decoder)
    }
    
    override  func evaluate(atTime:TimeInterval,
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
