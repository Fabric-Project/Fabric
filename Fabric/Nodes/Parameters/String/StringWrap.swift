//
//  StringWrap.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI

// MARK: - Settings View

struct StringWrapSettingsView: View {
    @Bindable var node: StringWrapNode

    var body: some View {
        VStack(alignment: .leading) {
            Text("Wrap at word boundaries using:")
            Text("**Characters** — line length in characters\n**Words** — number of words per line\n**Aspect** — overall aspect ratio (characters across vs. lines down)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Picker("", selection: $node.mode) {
                ForEach(WrapMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - String Wrap Node

@Observable public class StringWrapNode: Node {
    override public class var name: String { "String Wrap" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Wrap a String by inserting newlines at word boundaries, configurable by character count, word count, or aspect ratio" }
    override public var settingsSize: SettingsViewSize { .Custom(size: CGSize(width: 400, height: 150)) }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case mode
    }

    public required init(context: Context) {
        super.init(context: context)
        self.updateLimitPort()
    }

    public required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decoded = try container.decodeIfPresent(String.self, forKey: .mode),
           let decodedMode = WrapMode(rawValue: decoded) {
            self.mode = decodedMode
        }
        self.updateLimitPort()
    }

    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.mode.rawValue, forKey: .mode)
    }

    // MARK: - Properties

    @ObservationIgnored fileprivate var mode: WrapMode = .Characters {
        didSet {
            if oldValue != mode {
                updateLimitPort()
            }
        }
    }

    // MARK: - Ports

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return ports + [
            ("inputPort", NodePort<String>(name: "String", kind: .Inlet, description: "Input string to wrap")),
            ("outputPort", NodePort<String>(name: "String", kind: .Outlet, description: "String with newlines inserted at word boundaries")),
        ]
    }

    public var inputPort: NodePort<String> { port(named: "inputPort") }
    public var outputPort: NodePort<String> { port(named: "outputPort") }

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView {
        AnyView(StringWrapSettingsView(node: self))
    }

    // MARK: - Dynamic Limit Port

    private static let limitPortName = "inputLimit"

    private func updateLimitPort() {
        // Remove existing limit port
        if let existing: Port = self.findPort(named: Self.limitPortName) {
            self.removePort(existing)
        }

        // Add the appropriate port for the current mode
        let port: Port
        switch mode {
        case .Characters:
            port = ParameterPort(parameter: IntParameter("Characters", 40, 1, 10000, .inputfield, "Maximum characters per line"))
        case .Words:
            port = ParameterPort(parameter: IntParameter("Words", 10, 1, 1000, .inputfield, "Maximum words per line"))
        case .Aspect:
            port = ParameterPort(parameter: FloatParameter("Aspect", 4.0, 0.01, 100.0, .inputfield, "Target aspect ratio (characters across / lines down)"))
        }
        self.addDynamicPort(port, name: Self.limitPortName)

        // Re-wrap with new setting
        self.inputPort.valueDidChange = true
    }

    // MARK: - Execution

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        guard let limitPort: Port = self.findPort(named: Self.limitPortName) else { return }
        guard inputPort.valueDidChange || limitPort.valueDidChange else { return }
        guard let string = inputPort.value else { return }

        let words = string.split(omittingEmptySubsequences: false, whereSeparator: \.isWhitespace)
                          .map(String.init)
        guard !words.isEmpty else {
            outputPort.send("")
            return
        }

        let charLimit: Int
        switch mode {
        case .Characters:
            let value = (limitPort as? ParameterPort<Int>)?.value ?? 40
            charLimit = max(1, value)
        case .Words:
            let value = (limitPort as? ParameterPort<Int>)?.value ?? 10
            charLimit = wordCountToCharLimit(words: words, wordLimit: max(1, value))
        case .Aspect:
            let value = (limitPort as? ParameterPort<Float>)?.value ?? 4.0
            charLimit = aspectToCharLimit(words: words, aspect: value)
        }

        outputPort.send(wrapWords(words, charLimit: charLimit))
    }

    /// Wrap words into lines, breaking at word boundaries at or after `charLimit` characters.
    private func wrapWords(_ words: [String], charLimit: Int) -> String {
        var lines: [String] = []
        var currentLine = ""

        for word in words {
            if currentLine.isEmpty {
                currentLine = word
            } else {
                if currentLine.count >= charLimit {
                    lines.append(currentLine)
                    currentLine = word
                } else {
                    currentLine += " " + word
                }
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        return lines.joined(separator: "\n")
    }

    /// Convert a word-count limit to a character limit by measuring the average word length.
    private func wordCountToCharLimit(words: [String], wordLimit: Int) -> Int {
        let totalChars = words.reduce(0) { $0 + $1.count }
        let avgWordLen = Double(totalChars) / Double(words.count)
        return max(1, Int((avgWordLen + 1) * Double(wordLimit)))
    }

    /// Calculate a character-per-line limit that fits the text within the target aspect ratio.
    /// aspect = characters across / lines down, so chars = sqrt(totalChars * aspect).
    private func aspectToCharLimit(words: [String], aspect: Float) -> Int {
        let totalChars = words.reduce(0) { $0 + $1.count } + max(0, words.count - 1)
        let charsAcross = sqrt(Double(totalChars) * Double(aspect))
        return max(1, Int(charsAcross))
    }
}

// MARK: - Wrap Modes

enum WrapMode: String, CaseIterable {
    case Characters = "Characters"
    case Words = "Words"
    case Aspect = "Aspect"
}
