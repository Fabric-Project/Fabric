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

public class SampleAndHold<ValueType : PortValue & Equatable & FabricDescription> : Node
{
    public override class var name:String { "Sample and Hold \(ValueType.fabricDescription)" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Sample a value from input \(ValueType.fabricDescription) if sampling is enabled, and output last sampled value."}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputValue", NodePort<ValueType>(name: "Value" , kind: .Inlet)),
            ("inputSample", ParameterPort(parameter:BoolParameter("Sample", true))),
            ("inputReset", ParameterPort(parameter:BoolParameter("Reset", false))),
            ("outputValue", NodePort<ValueType>(name: "Value" , kind: .Outlet)),
        ]
    }
    
    // Params
    public var inputValue:NodePort<ValueType> { port(named: "inputValue") }
    public var inputSample:ParameterPort<Bool> { port(named: "inputSample") }
    public var inputReset:ParameterPort<Bool> { port(named: "inputReset") }
    public var outputValue:NodePort<ValueType> { port(named: "outputValue") }

    private var value:ValueType?
        
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        
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
