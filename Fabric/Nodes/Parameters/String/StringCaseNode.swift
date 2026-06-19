//
//  StringCaseNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class StringCaseNode: Node {
    override public class var name: String { "String Case" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Convert the case of a String" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputPort", ParameterPort(parameter: StringParameter("String", "", .inputfield, "Input string to convert"))),
            ("inputCase", ParameterPort(parameter: StringParameter("Case", "Uppercase", StringCaseMode.allCases.map(\.rawValue), .dropdown, "Case conversion to apply"))),
            ("outputPort", NodePort<String>(name: "String", kind: .Outlet, description: "Case-converted string")),
        ]
    }

    // Port proxies
    public var inputPort: ParameterPort<String> { port(named: "inputPort") }
    public var inputCase: ParameterPort<String> { port(named: "inputCase") }
    public var outputPort: NodePort<String> { port(named: "outputPort") }

    private var mode = StringCaseMode.Uppercase

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        if inputCase.valueDidChange,
           let param = inputCase.value,
           let newMode = StringCaseMode(rawValue: param) {
            mode = newMode
        }

        if inputCase.valueDidChange || inputPort.valueDidChange,
           let string = inputPort.value {
            outputPort.send(mode.convert(string))
        }
    }
}

// MARK: - Case Modes

enum StringCaseMode: String, CaseIterable {
    case Uppercase = "Uppercase"
    case Lowercase = "Lowercase"
    case Capitalized = "Capitalized"

    func convert(_ string: String) -> String {
        switch self {
        case .Uppercase:   return string.uppercased()
        case .Lowercase:   return string.lowercased()
        case .Capitalized: return string.capitalized
        }
    }
}
