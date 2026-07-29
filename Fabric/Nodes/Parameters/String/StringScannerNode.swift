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
    @Bindable var model: StringScannerNode.SettingsModel

    var body: some View {
        VStack(alignment: .leading) {
            Text("Use `{name}` for String, `{name:s}` String, `{name:d}` or `{name:i}` Int, `{name:b}` Bool, `{name:f}` Float.\n\nExample: `Frame {n:d} at {t:f}s`\n\nEscapes: `\\n`, `\\r`, `\\t`, `\\\\`, and `\\{` `\\}` for literal braces.\n\nThe format string is converted to a regex that captures values from the input string.")

            Spacer()

            TextField("Format String", text: $model.formatString)
                .lineLimit(1)
                .font(.system(size: 10))
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

// MARK: - String Scanner Node

public class StringScannerNode: Node {
    override public class var name: String { "String Scanner" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Extract values from a string using named placeholders. Inverse of String Formatter." }

    override public var displayName: String? { formatString.isEmpty ? nil : formatString }

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

    /// Procedural construction with a specific format string — the Settings-view
    /// state that shapes this node's ports, so graph building never has to go
    /// through the inspector to reach it.
    public init(context: Context, formatString: String) {
        self.formatString = formatString
        super.init(context: context)
        self.updatePorts()
    }

    // MARK: - Properties

    public fileprivate(set) var formatString: String = "Frame {n:d} at {t:f}s" {
        didSet {
            self.updatePorts()
            self.nameSubject.send()
        }
    }

    /// Sets the format string from outside the Settings view — the procedural
    /// equivalent of typing in the inspector.
    public func setFormatString(_ formatString: String) {
        guard formatString != self.formatString else { return }
        self.formatString = formatString
    }

    private var parsedFormatString = ParsedFormatString(tokens: [])
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

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView {
        AnyView(StringScannerSettingsView(model: _settingsModel))
    }

    // MARK: - Settings Model

    @Observable final class SettingsModel
    {
        var formatString: String
        {
            didSet
            {
                guard formatString != node?.formatString else { return }
                node?.formatString = formatString
            }
        }
        private weak var node: StringScannerNode?

        init(node: StringScannerNode)
        {
            self.node = node
            self.formatString = node.formatString
        }
    }

    private lazy var _settingsModel = SettingsModel(node: self)

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

    private func updatePorts() {
        let newParse = parseFormatString(formatString)
        let newPlaceholders = newParse.placeholders

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

        self.parsedFormatString = newParse
        self.buildRegex()

        // The input is unchanged but the regex reading it is not, and the
        // renderer skips a node that is not dirty — so re-scan what is there.
        self.inputString.valueDidChange = true
        self.markDirty()
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
        // now matchable, so a String capture must be able to span one too.
        self.scanRegex = try? Regex(regexString).dotMatchesNewlines()
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
