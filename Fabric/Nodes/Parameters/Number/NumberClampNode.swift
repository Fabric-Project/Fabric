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
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputNumber", ParameterPort(parameter: FloatParameter("Input Number", 0.0, .inputfield))),
            ("inputMinNumber", ParameterPort(parameter: FloatParameter("Min Number", 0.0, .inputfield))),
            ("inputMaxNumber", ParameterPort(parameter: FloatParameter("Max Number", 0.0, .inputfield))),
            ("outputNumber", NodePort<Float>(name: NumberNode.name , kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputNumber:ParameterPort<Float> { port(named: "inputNumber") }
    public var inputMinNumber:ParameterPort<Float> { port(named: "inputMinNumber") }
    public var inputMaxNumber:ParameterPort<Float> { port(named: "inputMaxNumber") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }
    
    override public func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
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
