//
//  FloatAddNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/2/25.
//

import Foundation
import Satin
import simd
import Metal

public class NumberLogicOperator : Node
{
    override public static var name:String { "Number Comparison" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Run an comparison on 2 inputs Number and return the result"}

    // Ports
    public let inputNumber1 = ParameterPort(parameter: FloatParameter("Number A", 0.0, .inputfield, "First value to compare"))
    public let inputNumber2 = ParameterPort(parameter: FloatParameter("Number B", 0.0, .inputfield, "Second value to compare"))
    public let inputParam = ParameterPort(parameter: StringParameter("Operator", BinaryMathLogicOperator.Equals.rawValue, BinaryMathLogicOperator.allCases.map(\.rawValue), .dropdown, "Comparison operation to perform"))
    public let outputResult = NodePort<Bool>(name: "Result" , kind: .Outlet, description: "Result of the comparison")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputNumber1", port: self.inputNumber1),
            PortDeclaration(key: "inputNumber2", port: self.inputNumber2),
            PortDeclaration(key: "inputParam", port: self.inputParam),
            PortDeclaration(key: "outputResult", port: self.outputResult),
        ]
    }

    private var mathOperator = BinaryMathLogicOperator.Equals
    
    override public func startExecution(renderer:GraphRenderer) throws
    {
        if let stringParam = self.inputParam.parameter as? StringParameter
        {
            stringParam.options = BinaryMathLogicOperator.allCases.map(\.rawValue)
        }
        try super.startExecution(renderer: renderer)
    }
         
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputParam.valueDidChange,
           let param = self.inputParam.value,
           let mathOp = BinaryMathLogicOperator(rawValue: param)
        {
            self.mathOperator = mathOp
        }
        
        if self.inputParam.valueDidChange
            || self.inputNumber1.valueDidChange
            || self.inputNumber2.valueDidChange,
           let number1 = self.inputNumber1.value
        {

            let number2 = self.inputNumber2.value ?? number1

            self.outputResult.send(self.mathOperator.perform(lhs: number1,
                                                             rhs: number2) )
        }
    }
}
