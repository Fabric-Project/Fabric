//
//  StringComponentNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//

import Foundation
import Satin
import simd
import Metal

public class StringSplitNode : Node
{
    override public static var name:String { "String Split" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Split a String into an array of Strings using a separator"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPort",       ParameterPort(parameter: StringParameter("String", "", .inputfield, "Input string to split"))),
            ("separatorPort",   ParameterPort(parameter: StringParameter("Separator", "\n", .inputfield, "Separator to split the string by"))),
            ("outputPort",      NodePort<ContiguousArray<String>>(name: "Strings", kind: .Outlet, description: "Array of string components")),
        ]
    }

    // Port Proxy
    public var inputPort:ParameterPort<String>                      { port(named: "inputPort") }
    public var separatorPort:NodePort<String>                       { port(named: "separatorPort") }
    public var outputPort:NodePort<ContiguousArray<String>>         { port(named: "outputPort") }


    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange || self.separatorPort.valueDidChange
        {
            if let string = self.inputPort.value,
               let separator = self.separatorPort.value
            {
                self.outputPort.send( ContiguousArray<String>(string.components(separatedBy: separator)) )
            }
        }
    }
}
