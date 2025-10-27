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

public class NumberUnnaryOperator : Node
{
    override public class var name:String { "Number Unnary Operator" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Run an operation on an input Number and return the resulting Number"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputNumber", ParameterPort(parameter: FloatParameter("Number", 0.0, .inputfield))),
            ("inputParam", ParameterPort(parameter: StringParameter("Operator", "Sine", UnaryMathOperator.allCases.map(\.rawValue))) ),
            ("outputNumber", NodePort<Float>(name: NumberNode.name , kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputNumber:ParameterPort<Float> { port(named: "inputNumber") }
    public var inputParam:ParameterPort<String> { port(named: "inputParam") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }
        
    private var mathOperator = UnaryMathOperator.Sine
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
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
