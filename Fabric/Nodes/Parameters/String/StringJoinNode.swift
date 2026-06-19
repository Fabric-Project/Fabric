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
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPort",       NodePort<ContiguousArray<String>>(name: "Strings", kind: .Inlet, description: "Array of strings to join")),
            ("separatorPort",   ParameterPort(parameter: StringParameter("Separator", ", ", .inputfield, "Separator to place between each string"))),
            ("outputPort",      NodePort<String>(name: "String", kind: .Outlet, description: "Joined string result")),
        ]
    }

    // Port Proxy
    public var inputPort:NodePort<ContiguousArray<String>>  { port(named: "inputPort") }
    public var separatorPort:NodePort<String>               { port(named: "separatorPort") }
    public var outputPort:NodePort<String>                  { port(named: "outputPort") }

    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange || self.separatorPort.valueDidChange
        {
            if let strings = self.inputPort.value,
               let separator = self.separatorPort.value
            {
                self.outputPort.send( strings.joined(separator: separator) )
            }
        }
    }
}
