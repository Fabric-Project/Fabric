//
//  StringLengthNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class StringTrimNode : Node
{
    override public static var name:String { "String Trim" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Remove Whitespace from a String"}

    // Ports
    public let inputPort = ParameterPort(parameter: StringParameter("String", "", .inputfield, "Input string to trim"))
    public let outputPort = NodePort<String>(name: "String", kind: .Outlet, description: "String with leading and trailing whitespace removed")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputPort", port: self.inputPort),
            PortDeclaration(key: "outputPort", port: self.outputPort),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputPort.valueDidChange
        {
            if let string = self.inputPort.value
            {
                self.outputPort.send( string.trimmingCharacters(in: .whitespacesAndNewlines) )
            }
//            else
//            {
//                self.outputPort.send( nil )
//            }
        }
    }
}
