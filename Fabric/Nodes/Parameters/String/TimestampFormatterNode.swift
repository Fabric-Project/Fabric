//
//  TimestampFormatterNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class TimestampFormatterNode: Node {
    override public class var name: String { "Timestamp Formatter" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Format a Unix timestamp as a date String" }

    // Ports
    public let inputSeconds = ParameterPort(parameter: IntParameter("Seconds", 0, .inputfield, "Unix timestamp whole seconds (e.g. from Clock Time)"))
    public let inputFormat = ParameterPort(parameter: StringParameter("Format", "yyyy-MM-dd HH:mm:ss", .inputfield, "Date format pattern (e.g. yyyy-MM-dd HH:mm:ss)"))
    public let outputPort = NodePort<String>(name: "String", kind: .Outlet, description: "Formatted date string")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputSeconds", port: self.inputSeconds),
            PortDeclaration(key: "inputFormat", port: self.inputFormat),
            PortDeclaration(key: "outputPort", port: self.outputPort),
        ]
    }

    private let formatter = DateFormatter()

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
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
