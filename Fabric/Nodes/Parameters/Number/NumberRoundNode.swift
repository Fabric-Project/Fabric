//
//  FloatAddNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/26/25.
//

import Foundation


import Foundation
import Satin
import simd
import Metal
import QuartzCore

public class NumberRoundNode : Node
{
    override public class var name:String { "Round Number" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Round a Number to an Index"}

    // Ports
    public let inputNumber = ParameterPort(parameter: FloatParameter("Number", 0, Float.leastNormalMagnitude, Float.greatestFiniteMagnitude, .inputfield, "Number to round"))
    public let inputRoundMethod = ParameterPort(parameter: StringParameter("Round Method", "Round", ["Round", "Floor", "Ceil"], .dropdown, "Rounding method (Round, Floor, or Ceiling)"))
    public let outputNumber = NodePort<Int>(name: "Number" , kind: .Outlet, description: "The rounded integer value")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputNumber", port: self.inputNumber),
            PortDeclaration(key: "inputRoundMethod", port: self.inputRoundMethod),
            PortDeclaration(key: "outputNumber", port: self.outputNumber),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputNumber.valueDidChange || self.inputRoundMethod.valueDidChange
        {
            if let roundMethod = self.inputRoundMethod.value,
                let inputValue = self.inputNumber.value
            {
                if roundMethod == "Round"
                {
                    self.outputNumber.send(Int(round(Float(inputValue))))
                }
                else if roundMethod == "Floor"
                {
                    self.outputNumber.send(Int(floor(Float(inputValue))))
                }
                else if roundMethod == "Ceil"
                {
                    self.outputNumber.send(Int(ceil(Float(inputValue))))
                }
            }
        }
    }
}
