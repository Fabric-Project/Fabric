//
//  StringFormatterNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class StringFormatterNode: Node {
    override public class var name: String { "String Formatter" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Format a Number as a String using a format specifier" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputValue", NodePort<Float>(name: "Value", kind: .Inlet, description: "Numeric value to format")),
            ("inputFormat", ParameterPort(parameter: StringParameter("Format", "%.2f", .inputfield, "Printf-style format specifier"))),
            ("outputPort", NodePort<String>(name: "String", kind: .Outlet, description: "Formatted string")),
        ]
    }

    // Port proxies
    public var inputValue: NodePort<Float> { port(named: "inputValue") }
    public var inputFormat: ParameterPort<String> { port(named: "inputFormat") }
    public var outputPort: NodePort<String> { port(named: "outputPort") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        if inputValue.valueDidChange || inputFormat.valueDidChange,
           let value = inputValue.value,
           let format = inputFormat.value {
            outputPort.send(String(format: format, value))
        }
    }
}
