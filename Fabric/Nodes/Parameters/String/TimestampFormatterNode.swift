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
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputSeconds", ParameterPort(parameter: IntParameter("Seconds", 0, .inputfield, "Unix timestamp whole seconds (e.g. from Clock Time)"))),
            ("inputFormat", ParameterPort(parameter: StringParameter("Format", "yyyy-MM-dd HH:mm:ss", .inputfield, "Date format pattern (e.g. yyyy-MM-dd HH:mm:ss)"))),
            ("outputPort", NodePort<String>(name: "String", kind: .Outlet, description: "Formatted date string")),
        ]
    }

    // Port proxies
    public var inputSeconds: ParameterPort<Int> { _inputSeconds }
    private var _inputSeconds: ParameterPort<Int>!
    public var inputFormat: ParameterPort<String> { _inputFormat }
    private var _inputFormat: ParameterPort<String>!
    public var outputPort: NodePort<String> { _outputPort }
    private var _outputPort: NodePort<String>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._inputSeconds = findPort(named: "inputSeconds")
        self._inputFormat = findPort(named: "inputFormat")
        self._outputPort = findPort(named: "outputPort")
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
