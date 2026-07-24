//
//  StringSplitNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class StringSplitNode: Node {
    override public class var name: String { "String Split" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Split a String into an Array of Strings using a separator. Inverse of String Join." }
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports + [
            ("inputPort", ParameterPort(parameter: StringParameter("String", "", .inputfield, "Input string to split"))),
            ("inputSeparator", ParameterPort(parameter: StringParameter("Separator", ", ", .inputfield, #"Separator string to split on. Supports \n, \r, \t, and \\ escape sequences"#))),
            ("outputPort", NodePort<ContiguousArray<String>>(name: "Strings", kind: .Outlet, description: "Array of string components")),
        ]
    }
    
    // Port proxies
    public var inputPort: ParameterPort<String> { port(named: "inputPort") }
    public var inputSeparator: ParameterPort<String> { port(named: "inputSeparator") }
    public var outputPort: NodePort<ContiguousArray<String>> { port(named: "outputPort") }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if inputPort.valueDidChange || inputSeparator.valueDidChange,
           let string = inputPort.value,
           let separator = inputSeparator.value {
            outputPort.send(Self.split(string, separator: separator))
        }
    }

    static func split(_ string: String, separator: String) -> ContiguousArray<String>
    {
        ContiguousArray(string.components(separatedBy: decodedSeparator(separator)))
    }

    static func decodedSeparator(_ separator: String) -> String
    {
        var decodedSeparator = ""
        var currentIndex = separator.startIndex

        while currentIndex < separator.endIndex
        {
            let character = separator[currentIndex]
            guard character == "\\" else
            {
                decodedSeparator.append(character)
                currentIndex = separator.index(after: currentIndex)
                continue
            }

            let escapedCharacterIndex = separator.index(after: currentIndex)
            guard escapedCharacterIndex < separator.endIndex else
            {
                decodedSeparator.append(character)
                break
            }

            switch separator[escapedCharacterIndex]
            {
            case "n":
                decodedSeparator.append("\n")
            case "r":
                decodedSeparator.append("\r")
            case "t":
                decodedSeparator.append("\t")
            case "\\":
                decodedSeparator.append("\\")
            default:
                decodedSeparator.append(character)
                decodedSeparator.append(separator[escapedCharacterIndex])
            }

            currentIndex = separator.index(after: escapedCharacterIndex)
        }

        return decodedSeparator
    }
}
