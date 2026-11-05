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
    public let inputValue = NodePort<PortValue>(name: "Value" , kind: .Inlet, description: "Value to monitor for changes")
    public let outputSignal = NodePort<Bool>(name: "Signal" , kind: .Outlet, description: "True when input value changed this frame")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputValue", port: self.inputValue),
            PortDeclaration(key: "outputSignal", port: self.outputSignal),
        ]
    }
    
    // Params

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let signal = self.inputValue.valueDidChange
        // Force to continue signalling when the input changes on successive frames
        self.outputSignal.send(signal, force: signal)
    }
}
