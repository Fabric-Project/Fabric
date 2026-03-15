//
//  StringSeparatorNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class StringSeparatorNode: Node {
    override public class var name: String { "String Separator" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Split a String into an Array of Strings using a separator" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputPort", NodePort<String>(name: "String", kind: .Inlet, description: "Input string to split")),
            ("inputSeparator", ParameterPort(parameter: StringParameter("Separator", ",", .inputfield, "Separator string to split on"))),
            ("outputPort", NodePort<ContiguousArray<String>>(name: "Components", kind: .Outlet, description: "Array of string components")),
        ]
    }

    // Port proxies
    public var inputPort: NodePort<String> { port(named: "inputPort") }
    public var inputSeparator: ParameterPort<String> { port(named: "inputSeparator") }
    public var outputPort: NodePort<ContiguousArray<String>> { port(named: "outputPort") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        if inputPort.valueDidChange || inputSeparator.valueDidChange,
           let string = inputPort.value,
           let separator = inputSeparator.value {
            outputPort.send(ContiguousArray<String>(string.components(separatedBy: separator)))
        }
    }
}
