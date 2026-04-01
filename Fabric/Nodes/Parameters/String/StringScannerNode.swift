//
//  StringScannerNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI

// MARK: - Settings View

struct StringScannerSettingsView: View {
    @Bindable var node: StringScannerNode

    var body: some View {
        VStack(alignment: .leading) {
            Text("Use `{name}` for String, `{name:s}` String, `{name:d}` or `{name:i}` Int, `{name:b}` Bool, `{name:f}` Float.\n\nExample: `Frame {n:d} at {t:f}s`\n\nThe format string is converted to a regex that captures values from the input string.")

            Spacer()

            TextField("Format String", text: $node.formatString)
                .lineLimit(1)
                .font(.system(size: 10))
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

// MARK: - String Scanner Node

@Observable public class StringScannerNode: Node {
    override public class var name: String { "String Scanner" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Extract values from a string using named placeholders. Inverse of String Formatter." }

    override public var name: String { formatString }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case formatString
    }

    public required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decodeIfPresent(String.self, forKey: .formatString)
        self.formatString = decoded ?? "Frame {n:d} at {t:f}s"
        self.updatePorts()
    }

    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.formatString, forKey: .formatString)
    }

    public required init(context: Context) {
        super.init(context: context)
        self.updatePorts()
    }

    // MARK: - Properties

    @ObservationIgnored fileprivate var formatString: String = "Frame {n:d} at {t:f}s" {
        didSet {
            self.updatePorts()
        }
    }

    @ObservationIgnored private var placeholders: [FormatPlaceholder] = []
    @ObservationIgnored private var scanRegex: Regex<AnyRegexOutput>? = nil

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

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView {
        AnyView(StringScannerSettingsView(node: self))
    }

    // MARK: - Execution

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
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

        // Extract captured values and send to output ports
        for (index, placeholder) in placeholders.enumerated() {
            let captureIndex = index + 1  // Index 0 is the whole match
            guard captureIndex < match.output.count else { continue }

            let captured = String(match.output[captureIndex].substring ?? "")

            switch placeholder.portType {
            case .Float:
                if let port = self.findPort(named: placeholder.name) as? NodePort<Float> {
                    port.send(Float(captured) ?? 0.0)
                }
            case .Int:
                if let port = self.findPort(named: placeholder.name) as? NodePort<Int> {
                    port.send(Int(captured) ?? 0)
                }
            case .Bool:
                if let port = self.findPort(named: placeholder.name) as? NodePort<Bool> {
                    let value = captured == "true" || captured == "1" || captured == "yes"
                    port.send(value)
                }
            default: // .String
                if let port = self.findPort(named: placeholder.name) as? NodePort<String> {
                    port.send(captured)
                }
            }
        }
    }

    // MARK: - Dynamic Port Management

    private func updatePorts() {
        let newPlaceholders = parseFormatPlaceholders(formatString)

        let staticPortNames: Set<String> = ["Matched"]
        let existingNames = Set(self.outputPorts().filter { !staticPortNames.contains($0.name) }.map { $0.name })
        let newNames = Set(newPlaceholders.map { $0.name })

        // Remove ports no longer in the format string
        let toRemove = existingNames.subtracting(newNames)
        for portName in toRemove {
            if let port: Port = self.findPort(named: portName) {
                self.removePort(port)
            }
        }

        // Remove ports whose type has changed
        for placeholder in newPlaceholders {
            if let existingPort: Port = self.findPort(named: placeholder.name),
               existingPort.portType != placeholder.portType {
                self.removePort(existingPort)
            }
        }

        // Add ports for new placeholders
        for placeholder in newPlaceholders {
            if (self.findPort(named: placeholder.name) as Port?) == nil {
                let port = makeOutputPort(for: placeholder)
                self.addDynamicPort(port, name: placeholder.name)
            }
        }

        self.placeholders = newPlaceholders
        self.buildRegex()
    }

    private func buildRegex() {
        let placeholderPattern = #/\{(\w+)(?::([^}]+))?\}/#

        var regexString = "^"
        var lastEnd = formatString.startIndex

        for match in formatString.matches(of: placeholderPattern) {
            // Escape the literal text between placeholders
            let literalRange = lastEnd..<match.range.lowerBound
            let literal = String(formatString[literalRange])
            regexString += NSRegularExpression.escapedPattern(for: literal)

            // Add a capture group appropriate to the type
            let name = String(match.1)
            if let placeholder = placeholders.first(where: { $0.name == name }) {
                switch placeholder.portType {
                case .Float:
                    regexString += "([+-]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][+-]?\\d+)?)"
                case .Int:
                    regexString += "([+-]?\\d+)"
                case .Bool:
                    regexString += "(true|false|yes|no|0|1)"
                default:
                    regexString += "(.+?)"
                }
            } else {
                regexString += "(.+?)"
            }

            lastEnd = match.range.upperBound
        }

        // Append any trailing literal text
        let trailing = String(formatString[lastEnd...])
        regexString += NSRegularExpression.escapedPattern(for: trailing)
        regexString += "$"

        self.scanRegex = try? Regex(regexString)
    }

    private func makeOutputPort(for placeholder: FormatPlaceholder) -> Port {
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
}
