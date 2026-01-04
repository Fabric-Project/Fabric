//
//  SampleAndHold.swift
//  Fabric
//
//  Created by Anton Marini on 10/16/25.
//

import Foundation
import Satin
import Metal
import simd

public class SampleAndHoldNode<Value : PortValueRepresentable & Equatable> : Node
{
    public override class var name:String { "Sample and Hold \(Value.portType.rawValue)" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Sample a value from input \(Value.portType.rawValue) if sampling is enabled, and output last sampled value."}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputValue", NodePort<Value>(name: "Value" , kind: .Inlet)),
//            ("inputValue", ParameterPort(parameter: GenericParameter<Value>("Value", Value.defaultValue, .inputfield))),
            ("inputSample", ParameterPort(parameter:BoolParameter("Sample", true, .button))),
            ("inputReset", ParameterPort(parameter:BoolParameter("Reset", false,  .button))),
            ("outputValue", NodePort<Value>(name: "Value" , kind: .Outlet)),
        ]
    }
    
    // Params
    public var inputValue:NodePort<Value> { port(named: "inputValue") }
    public var inputSample:ParameterPort<Bool> { port(named: "inputSample") }
    public var inputReset:ParameterPort<Bool> { port(named: "inputReset") }
    public var outputValue:NodePort<Value> { port(named: "outputValue") }

    private var value:Value?
        
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputSample.valueDidChange
        {
            if let sample = self.inputSample.value
            {
                self.inputSample.value = sample
            }
        }
        
        if self.inputValue.valueDidChange,
           let inputValue = self.inputValue.value,
           let inputSampling = self.inputSample.value
        {
            if inputSampling
            {
                self.value = inputValue
                self.outputValue.send(self.value)
            }
        }
        
        if self.inputReset.valueDidChange,
           let inputReset = self.inputReset.value
        {
            if inputReset
            {
                self.value = nil
                self.outputValue.send(self.value)
            }
        }
        
    }
}
