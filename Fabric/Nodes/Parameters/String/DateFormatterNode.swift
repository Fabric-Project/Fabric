//
//  DateFormatterNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class DateFormatterNode: Node {
    override public class var name: String { "Date Formatter" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Format a Unix timestamp as a date String" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputSeconds", NodePort<Int>(name: "Seconds", kind: .Inlet, description: "Unix timestamp whole seconds (e.g. from Clock Time)")),
            ("inputFormat", ParameterPort(parameter: StringParameter("Format", "yyyy-MM-dd HH:mm:ss", .inputfield, "Date format pattern (e.g. yyyy-MM-dd HH:mm:ss)"))),
            ("outputPort", NodePort<String>(name: "String", kind: .Outlet, description: "Formatted date string")),
        ]
    }

    // Port proxies
    public var inputSeconds: NodePort<Int> { port(named: "inputSeconds") }
    public var inputFormat: ParameterPort<String> { port(named: "inputFormat") }
    public var outputPort: NodePort<String> { port(named: "outputPort") }

    private let formatter = DateFormatter()

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        if inputFormat.valueDidChange,
           let format = inputFormat.value {
            formatter.dateFormat = format
        }

        if inputSeconds.valueDidChange || inputFormat.valueDidChange,
           let seconds = inputSeconds.value {
            let date = Date(timeIntervalSince1970: TimeInterval(seconds))
            outputPort.send(formatter.string(from: date))
        }
    }
}
