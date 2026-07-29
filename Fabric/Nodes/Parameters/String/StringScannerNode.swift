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

    /// Placeholders are what the scan captures, so each builds an outlet —
    /// alongside Matched, which the format string does not own.
    override public class var placeholderPortKind: PortKind { .Outlet }
    override public class var staticPortNames: Set<String> { ["Matched"] }

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

    public var inputString: ParameterPort<String> { port(named: "inputString") }
    public var outputMatched: NodePort<Bool> { port(named: "outputMatched") }

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
        var captureIndex = 0  // Index 0 is the whole match

        for token in parsedFormatString.tokens {
            guard case .placeholder(let occurrence) = token else { continue }

            captureIndex += 1
            guard captureIndex < match.output.count else { continue }

            send(String(match.output[captureIndex].substring ?? ""), toPortNamed: occurrence.name)
        }
    }

    /// Sends captured text to the port `name` owns, converted to that port's type.
    private func send(_ captured: String, toPortNamed name: String) {
        switch parsedFormatString.placeholder(named: name)?.portType ?? .String {
        case .Float:
            if let port = self.findPort(named: name) as? NodePort<Float> {
                port.send(Float(captured) ?? 0.0)
            }
        case .Int:
            if let port = self.findPort(named: name) as? NodePort<Int> {
                port.send(Int(captured) ?? 0)
            }
        case .Bool:
            if let port = self.findPort(named: name) as? NodePort<Bool> {
                let value = captured == "true" || captured == "1" || captured == "yes"
                port.send(value)
            }
        default: // .String
            if let port = self.findPort(named: name) as? NodePort<String> {
                port.send(captured)
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
