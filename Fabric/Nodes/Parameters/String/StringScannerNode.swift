//
//  StringScannerNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI

// MARK: - String Scanner Node

public class StringScannerNode: BaseFormatStringNode {
    override public class var name: String { "String Scanner" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Extract values from a string using named placeholders. Inverse of String Formatter." }

    override public class var defaultFormatString: String { "Frame {n:d} at {t:f}s" }

    override public class var settingsGuidance: String {
        "Use `{name}` for String, `{name:s}` String, `{name:d}` or `{name:i}` Int, `{name:b}` Bool, `{name:f}` Float.\n\nExample: `Frame {n:d} at {t:f}s`\n\nEscapes: `\\n`, `\\r`, `\\t`, `\\\\`, and `\\{` `\\}` for literal braces.\n\nThe format string is converted to a regex that captures values from the input string."
    }

    private var scanRegex: Regex<AnyRegexOutput>? = nil

    // MARK: - Ports

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return ports + [
            ("inputString", ParameterPort(parameter: StringParameter("String", "", .inputfield, "The string to scan"))),
            ("outputMatched", NodePort<Bool>(name: "Matched", kind: .Outlet, description: "True if the input string matched the format")),
        ]
    }

    public var inputString: ParameterPort<String> { _inputString }
    private var _inputString: ParameterPort<String>!
    public var outputMatched: NodePort<Bool> { _outputMatched }
    private var _outputMatched: NodePort<Bool>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._inputString = findPort(named: "inputString")
        self._outputMatched = findPort(named: "outputMatched")
    }

    // MARK: - Execution

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard inputString.valueDidChange,
              let input = inputString.value,
              let regex = scanRegex else {
            return
        }

        guard let match = try? regex.wholeMatch(in: input) else {
            outputMatched.send(false)
            return
        }

        outputMatched.send(true)

        // Extract captured values and send to output ports. buildRegex emits one
        // capture group per placeholder *occurrence*, so the groups are walked in
        // that same order — a name written twice captures twice, independently,
        // and its port takes the last of them.
        for (index, occurrence) in boundOccurrences.enumerated() {
            let captureIndex = index + 1  // Index 0 is the whole match
            guard captureIndex < match.output.count, let port = occurrence.port else { continue }
            let captured = String(match.output[captureIndex].substring ?? "")

            switch port {
            case .float(let port): port.send(Float(captured) ?? 0.0)
            case .int(let port): port.send(Int(captured) ?? 0)
            case .bool(let port): port.send(captured == "true" || captured == "1" || captured == "yes")
            case .string(let port): port.send(captured)
            }
        }
    }

    // MARK: - Dynamic Port Management

    /// A placeholder's capture leaves on an outlet of its type.
    override func makePlaceholderPort(for placeholder: FormatPlaceholder) -> Port {
        switch placeholder.portType {
        case .Float:
            return NodePort<Float>(name: placeholder.name, kind: .Outlet, description: "Captured float value")
        case .Int:
            return NodePort<Int>(name: placeholder.name, kind: .Outlet, description: "Captured integer value")
        case .Bool:
            return NodePort<Bool>(name: placeholder.name, kind: .Outlet, description: "Captured boolean value")
        default:
            return NodePort<String>(name: placeholder.name, kind: .Outlet, description: "Captured string value")
        }
    }

    override func formatStringDidChange() {
        self.buildRegex()

        // The input is unchanged but the regex reading it is not, so re-scan
        // what is already there.
        self.inputString.valueDidChange = true
    }

    private func buildRegex() {
        var regexString = "^"

        for token in parsedFormatString.tokens {
            switch token {
            case .literal(let text):
                // Decoded literal text, taken as-is: whatever the user typed
                // matches itself, regex metacharacters included.
                regexString += NSRegularExpression.escapedPattern(for: text)

            case .placeholder(let placeholder):
                // A capture group appropriate to the type owning the port.
                switch parsedFormatString.placeholder(named: placeholder.name)?.portType ?? .String {
                case .Float:
                    regexString += "([+-]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][+-]?\\d+)?)"
                case .Int:
                    regexString += "([+-]?\\d+)"
                case .Bool:
                    regexString += "(true|false|yes|no|0|1)"
                default:
                    regexString += "(.+?)"
                }
            }
        }

        regexString += "$"

        // Newlines are ordinary characters here: a `\n` in the format string is
        // matchable, so a String capture must be able to span one too.
        self.scanRegex = try? Regex(regexString).dotMatchesNewlines()
    }
}
