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
    public let inputPort = ParameterPort(parameter: StringParameter("String", "", .inputfield, "Input string to convert"))
    public let inputCase = ParameterPort(parameter: StringParameter("Case", "Uppercase", StringCaseMode.allCases.map(\.rawValue), .dropdown, "Case conversion to apply"))
    public let outputPort = NodePort<String>(name: "String", kind: .Outlet, description: "Case-converted string")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputPort", port: self.inputPort),
            PortDeclaration(key: "inputCase", port: self.inputCase),
            PortDeclaration(key: "outputPort", port: self.outputPort),
        ]
    }

    private var mode = StringCaseMode.Uppercase

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
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
