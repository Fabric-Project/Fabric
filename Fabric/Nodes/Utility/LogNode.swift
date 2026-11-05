//
//  LogNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/10/25.
//


import Foundation
import Satin
import simd
import Metal




public class LogNode : Node
{
    override public class var name:String { "Log" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Log Values to the Console"}

    // Ports
    public let inputAny = NodePort<PortValue>(name: "Log Value", kind: .Inlet, description: "Value to print to console")

    public override func declaredPorts() -> [PortDeclaration]
    {
        [PortDeclaration(key: "inputAnyPort", port: self.inputAny)] + super.declaredPorts()
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputAny.valueDidChange,
           let value = self.inputAny.value
        {
            print("\(self) - Frame \(executionInfo.timing.frameNumber): \(self.inputAny.portType.fullString(for: value))" )
        }
    }
}
