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
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputNumber", NodePort<Float>(name: NumberNode.name , kind: .Inlet, description: "Number to round")),
            ("inputRoundMethod", ParameterPort(parameter: StringParameter("Round Method", "Round", ["Round", "Floor", "Ceil"], .dropdown, "Rounding method (Round, Floor, or Ceiling)"))),
            ("outputNumber", NodePort<Int>(name: NumberNode.name , kind: .Outlet, description: "The rounded integer value")),
        ]
    }
    
    // Port Proxy
    public var inputNumber:ParameterPort<Float> { port(named: "inputNumber") }
    public var inputRoundMethod:ParameterPort<String> { port(named: "inputRoundMethod") }
    public var outputNumber:NodePort<Int> { port(named: "outputNumber") }
    
    override public func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
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
