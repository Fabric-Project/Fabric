//
//  StringJoinNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class StringJoinNode : Node
{
    override public static var name:String { "String Join" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Join an array of Strings into a single String using a separator. Inverse of String Split. To join two or more string inputs, use String Formatter node."}

    // Ports
    public let inputPort = NodePort<ContiguousArray<String>>(name: "Strings", kind: .Inlet, description: "Array of strings to join")
    public let separatorPort: NodePort<String> = ParameterPort(parameter: StringParameter("Separator", ", ", .inputfield, #"Separator to place between each string. Supports \n, \r, \t, and \\ escape sequences"#))
    public let outputPort = NodePort<String>(name: "String", kind: .Outlet, description: "Joined string result")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputPort", port: self.inputPort),
            PortDeclaration(key: "separatorPort", port: self.separatorPort),
            PortDeclaration(key: "outputPort", port: self.outputPort),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputPort.valueDidChange || self.separatorPort.valueDidChange
        {
            if let strings = self.inputPort.value,
               let separator = self.separatorPort.value
            {
                // Same escape vocabulary as String Split's separator, so a
                // separator that splits a string joins it back together.
                self.outputPort.send( strings.joined(separator: decodeEscapeSequences(separator)) )
            }
        }
    }
}
