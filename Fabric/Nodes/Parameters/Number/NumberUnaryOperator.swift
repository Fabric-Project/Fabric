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

public class NumberUnaryOperator : Node
{
    override public class var name:String { "Number Unary Operator" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Run an operation on an input Number and return the resulting Number"}

    // Ports
    public let inputNumber = ParameterPort(parameter: FloatParameter("Number", 0.0, .inputfield, "Input value for the unary operation"))
    public let inputParam = ParameterPort(parameter: StringParameter("Operator", "Sine", UnaryMathOperator.allCases.map(\.rawValue), .dropdown, "Mathematical function to apply"))
    public let outputNumber = NodePort<Float>(name: "Number" , kind: .Outlet, description: "Result of the unary operation")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputNumber", port: self.inputNumber),
            PortDeclaration(key: "inputParam", port: self.inputParam),
            PortDeclaration(key: "outputNumber", port: self.outputNumber),
        ]
    }

    private var mathOperator = UnaryMathOperator.Sine
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if  self.inputParam.valueDidChange,
            let param = self.inputParam.value,
            let mathOp = UnaryMathOperator(rawValue: param)
        {
            self.mathOperator = mathOp
        }
        
        if self.inputNumber.valueDidChange || self.inputParam.valueDidChange,
           let number = self.inputNumber.value
        {
            self.outputNumber.send(  self.mathOperator.perform(number) )

        }
        
    }
}
