//
//  CurrentTimeNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/2/25.
//

import Foundation
import Satin
import simd
import Metal
import QuartzCore

public class NumberSmoothNode : Node
{
    override public class var name:String { "Smooth Number" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Smooth a number over time using a 1€ Filter"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputNumber", ParameterPort(parameter: FloatParameter("Number", 0, .inputfield))),
            ("inputFrequency", ParameterPort(parameter: FloatParameter("Frequency", 120.0, .inputfield))),
            ("outputNumber", NodePort<Float>(name: NumberNode.name , kind: .Outlet)),
        ]
    }
    
    // Init with 120 Hz?
    private let oneEuroFilter = OneEuroFilter(freq: 120.0)
    
    // Port Proxy
    public var inputNumber:ParameterPort<Float> { port(named: "inputNumber") }
    public var inputFrequency:ParameterPort<Float> { port(named: "inputFrequency") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }
    
    
    override public func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputFrequency.valueDidChange,
           let inputFrequency = self.inputFrequency.value
        {
            self.oneEuroFilter.setFrequency(Double(inputFrequency))
        }
        
        if let inputNumber = self.inputNumber.value
        {
            let filtered = oneEuroFilter.Filter(Double(inputNumber), timestamp: context.timing.systemTime)

            self.outputNumber.send( Float(filtered) )
        }
    }
}
