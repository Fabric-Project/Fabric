//
//  StringFormatterNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI

// MARK: - Shared format string parsing

/// A parsed placeholder from a format string like "Hello {name:.2f}"
struct FormatPlaceholder: Equatable {
    let name: String
    let formatSpecifier: String?  // e.g. ".2f", "d", "s", "b" — nil means default (String)

    /// The port type implied by the format specifier
    var portType: PortType {
        guard let spec = formatSpecifier else { return .String }
        let trimmed = spec.trimmingCharacters(in: .whitespaces)
        if trimmed == "b" { return .Bool }
        if trimmed == "d" { return .Int }
        if trimmed == "s" { return .String }
        // Anything containing 'f', 'e', 'g' (printf float specifiers) → Float
        let lastChar = trimmed.last
        if lastChar == "f" || lastChar == "e" || lastChar == "g" { return .Float }
        return .String
    }

    /// The printf format string to use with String(format:), or nil for plain string conversion
    var printfFormat: String? {
        guard let spec = formatSpecifier else { return nil }
        let trimmed = spec.trimmingCharacters(in: .whitespaces)
        if trimmed == "s" || trimmed == "b" { return nil }
        if trimmed == "d" { return "%d" }
        let lastChar = trimmed.last
        if lastChar == "f" || lastChar == "e" || lastChar == "g" {
            return "%\(trimmed)"
        }
        return nil
    }
}

/// Parse placeholders from a format string. Matches `{name}` and `{name:spec}`.
func parseFormatPlaceholders(_ formatString: String) -> [FormatPlaceholder] {
    let pattern = /\{(\w+)(?::([^}]+))?\}/
    var placeholders: [FormatPlaceholder] = []
    var seen = Set<String>()

    for match in formatString.matches(of: pattern) {
        let name = String(match.1)
        if seen.contains(name) { continue }
        seen.insert(name)
        let spec = match.2.map { String($0) }
        placeholders.append(FormatPlaceholder(name: name, formatSpecifier: spec))
    }
    return placeholders
}

// MARK: - Settings View

struct StringFormatSettingsView: View {
    @Bindable var node: StringFormatterNode

    var body: some View {
        VStack(alignment: .leading) {
            Text("Use `{name}` for String, `{name:s}` String, `{name:d}` Int, `{name:b}` Bool, `{name:f}` or `{name:.2f}` Float.\n\nExample: `Position: {x:.2f}, {y:.2f}`")

            Spacer()

            TextField("Format String", text: $node.formatString)
                .lineLimit(1)
                .font(.system(size: 10))
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

// MARK: - String Formatter Node

@Observable public class StringFormatterNode: Node {
    override public class var name: String { "String Formatter" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Format values into a string using named placeholders" }

    override public var name: String { formatString }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case formatString
    }

    public required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decodeIfPresent(String.self, forKey: .formatString)
        self.formatString = decoded ?? "Hello {name}"
        self.updatePorts()
    }

    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.formatString, forKey: .formatString)
    }

    public required init(context: Context) {
        super.init(context: context)
    }

    // MARK: - Properties

    @ObservationIgnored fileprivate var formatString: String = "Hello {name}" {
        didSet {
            self.updatePorts()
        }
    }

    @ObservationIgnored private var placeholders: [FormatPlaceholder] = []

    // MARK: - Ports

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return ports + [
            ("outputString", NodePort<String>(name: "String", kind: .Outlet, description: "The formatted output string")),
        ]
    }

    public var outputString: NodePort<String> { port(named: "outputString") }

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView {
        AnyView(StringFormatSettingsView(node: self))
    }

    // MARK: - Execution

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        let inputs = self.inputPorts()
        let anyChanged = inputs.compactMap(\.valueDidChange).contains(true)

        guard anyChanged else { return }

        var result = formatString
        let pattern = /\{(\w+)(?::([^}]+))?\}/

        for match in formatString.matches(of: pattern) {
            let name = String(match.1)
            let placeholder = placeholders.first(where: { $0.name == name })

            let replacement: String
            switch placeholder?.portType ?? .String {
            case .Float:
                if let port = self.findPort(named: name) as? NodePort<Float>,
                   let value = port.value {
                    if let fmt = placeholder?.printfFormat {
                        replacement = String(format: fmt, value)
                    } else {
                        replacement = String(value)
                    }
                } else {
                    replacement = ""
                }
            case .Int:
                if let port = self.findPort(named: name) as? NodePort<Int>,
                   let value = port.value {
                    if let fmt = placeholder?.printfFormat {
                        replacement = String(format: fmt, value)
                    } else {
                        replacement = String(value)
                    }
                } else {
                    replacement = ""
                }
            case .Bool:
                if let port = self.findPort(named: name) as? NodePort<Bool>,
                   let value = port.value {
                    replacement = String(value)
                } else {
                    replacement = ""
                }
            default: // .String
                if let port = self.findPort(named: name) as? NodePort<String>,
                   let value = port.value {
                    replacement = value
                } else {
                    replacement = ""
                }
            }

            result = result.replacingOccurrences(of: String(match.0), with: replacement)
        }

        outputString.send(result)
    }

    // MARK: - Dynamic Port Management

    private func updatePorts() {
        let newPlaceholders = parseFormatPlaceholders(formatString)

        let existingNames = Set(self.inputPorts().map { $0.name })
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
                let port = makeInputPort(for: placeholder)
                self.addDynamicPort(port, name: placeholder.name)
            }
        }

        self.placeholders = newPlaceholders
    }

    private func makeInputPort(for placeholder: FormatPlaceholder) -> Port {
        switch placeholder.portType {
        case .Float:
            return ParameterPort(parameter: FloatParameter(placeholder.name, 0.0, .inputfield))
        case .Int:
            return ParameterPort(parameter: IntParameter(placeholder.name, 0, .inputfield))
        case .Bool:
            return ParameterPort(parameter: BoolParameter(placeholder.name, false, .button))
        default:
            return ParameterPort(parameter: StringParameter(placeholder.name, "", .inputfield))
        }
    }
}
