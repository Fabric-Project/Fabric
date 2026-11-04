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

public class NumberClampNode : Node
{
    override public class var name:String { "Clamp Number" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Clamp a number between two values"}

    // Ports
    public let inputNumber = ParameterPort(parameter: FloatParameter("Input Number", 0.0, .inputfield, "The input value to clamp"))
    public let inputMinNumber = ParameterPort(parameter: FloatParameter("Min Number", 0.0, .inputfield, "Minimum allowed output value"))
    public let inputMaxNumber = ParameterPort(parameter: FloatParameter("Max Number", 1.0,  .inputfield, "Maximum allowed output value"))
    public let outputNumber = NodePort<Float>(name: "Number" , kind: .Outlet, description: "The clamped output value")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputNumber", port: self.inputNumber),
            PortDeclaration(key: "inputMinNumber", port: self.inputMinNumber),
            PortDeclaration(key: "inputMaxNumber", port: self.inputMaxNumber),
            PortDeclaration(key: "outputNumber", port: self.outputNumber),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputNumber.valueDidChange || self.inputMinNumber.valueDidChange || self.inputMaxNumber.valueDidChange
        {
            if let minValue = self.inputMinNumber.value,
                let maxValue = self.inputMaxNumber.value,
                let inputValue = self.inputNumber.value
            {
                self.outputNumber.send(  Float.minimum(Float.maximum(inputValue, minValue), maxValue) )
            }
            
        }
    }
}
