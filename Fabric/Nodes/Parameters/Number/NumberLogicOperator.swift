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
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputNumber1", ParameterPort(parameter: FloatParameter("Number A", 0.0, .inputfield, "First value to compare"))),
            ("inputNumber2", ParameterPort(parameter: FloatParameter("Number B", 0.0, .inputfield, "Second value to compare"))),
            ("inputParam", ParameterPort(parameter: StringParameter("Operator", BinaryMathLogicOperator.Equals.rawValue, BinaryMathLogicOperator.allCases.map(\.rawValue), .dropdown, "Comparison operation to perform")) ),
            ("outputResult", NodePort<Bool>(name: "Result" , kind: .Outlet, description: "Result of the comparison")),
        ]
    }
    
    // Port Proxy
    public var inputNumber1:ParameterPort<Float> { port(named: "inputNumber1") }
    public var inputNumber2:ParameterPort<Float> { port(named: "inputNumber2") }
    public var inputParam:ParameterPort<String> { port(named: "inputParam") }
    public var outputResult:NodePort<Bool> { port(named: "outputResult") }
    
    private var mathOperator = BinaryMathLogicOperator.Equals
    
    override public func startExecution(context: GraphExecutionContext) {
        super.startExecution(context: context)
        
        if let stringParam = self.inputParam.parameter as? StringParameter
        {
            stringParam.options = BinaryMathLogicOperator.allCases.map(\.rawValue)
        }
    }
         
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
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
