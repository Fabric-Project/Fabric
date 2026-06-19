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

public class SignalNode : Node
{
    public override class var name:String { "Signal" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Boolean Signal if a value has updated"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputValue", NodePort<PortValue>(name: "Value" , kind: .Inlet, description: "Value to monitor for changes")),
            ("outputSignal", NodePort<Bool>(name: "Signal" , kind: .Outlet, description: "True when input value changed this frame")),
        ]
    }
    
    // Params
    public var inputValue:NodePort<PortValue> { port(named: "inputValue") }
    public var outputSignal:NodePort<Bool> { port(named: "outputSignal") }
        
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let signal = self.inputValue.valueDidChange
        print("Signal \(signal)")
        self.outputSignal.send(signal, force: true)
    }
}
