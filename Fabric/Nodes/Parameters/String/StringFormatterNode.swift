//
//  StringFormatterNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI

// MARK: - Shared format string parsing

/// What a placeholder's specifier asks for: the type of the port it builds and,
/// for the numeric kinds, how to render the value.
///
/// The specifier is user-typed and reaches `String(format:)`, whose conversions
/// are read positionally against a single argument — so a specifier is only
/// honoured once it has been parsed whole and found to hold exactly one
/// conversion. Anything else falls back to `.string`, printing the value as
/// written rather than reading a vararg that was never supplied.
enum FormatSpecifier: Equatable {
    case string
    case bool
    /// printf format for a Swift Int, with the `l` length modifier its 64 bits need.
    case integer(printfFormat: String)
    case floatingPoint(printfFormat: String)

    /// printf flags this accepts before the width; all are argument-free.
    private static let flagCharacters: Set<Character> = ["-", "+", " ", "0", "#"]

    init(_ specifier: String?) {
        guard let specifier else { self = .string; return }

        let trimmed = specifier.trimmingCharacters(in: .whitespaces)
        guard trimmed != "s" else { self = .string; return }
        guard trimmed != "b" else { self = .bool; return }

        // <flags><width>.<precision><conversion>, and nothing else.
        var remainder = Substring(trimmed)

        let flags = remainder.prefix { Self.flagCharacters.contains($0) }
        remainder = remainder.dropFirst(flags.count)

        let width = remainder.prefix(while: \.isNumber)
        remainder = remainder.dropFirst(width.count)

        var precision = Substring()
        if remainder.first == "." {
            let digits = remainder.dropFirst().prefix(while: \.isNumber)
            precision = remainder.prefix(1 + digits.count)
            remainder = remainder.dropFirst(precision.count)
        }

        guard let conversion = remainder.first, remainder.count == 1 else { self = .string; return }

        switch conversion {
        case "d", "i":
            self = .integer(printfFormat: "%\(flags)\(width)\(precision)ld")
        case "f", "e", "g", "E", "G":
            self = .floatingPoint(printfFormat: "%\(flags)\(width)\(precision)\(conversion)")
        default:
            self = .string
        }
    }

    var portType: PortType {
        switch self {
        case .string: return .String
        case .bool: return .Bool
        case .integer: return .Int
        case .floatingPoint: return .Float
        }
    }
}

/// A parsed placeholder from a format string like "Hello {name:.2f}"
struct FormatPlaceholder: Equatable {
    let name: String
    let formatSpecifier: String?  // e.g. ".2f", "d", "s", "b" — nil means default (String)

    /// What the specifier asks for, or `.string` if it asks for nothing legible.
    var specifier: FormatSpecifier { FormatSpecifier(formatSpecifier) }

    /// The port type implied by the format specifier
    var portType: PortType { specifier.portType }

    /// The printf format string to use with String(format:), or nil for plain string conversion
    var printfFormat: String? {
        switch specifier {
        case .integer(let printfFormat), .floatingPoint(let printfFormat):
            return printfFormat
        case .string, .bool:
            return nil
        }
    }
}

/// A format string broken into the literal text and the `{name}` / `{name:spec}`
/// occurrences it is made of, in source order. Both String Formatter and String
/// Scanner walk this: one substitutes values into the placeholders, the other
/// builds a regex that captures them back out.
struct ParsedFormatString: Equatable {
    enum Token: Equatable {
        /// Literal text, escape sequences already decoded.
        case literal(String)
        /// One placeholder occurrence — a name may occur more than once.
        case placeholder(FormatPlaceholder)
    }

    let tokens: [Token]

    /// Placeholders in first-appearance order, one entry per name — the set of
    /// ports the node exposes. A repeated name keeps its first specifier, so the
    /// port type stays put no matter how a later occurrence is written.
    var placeholders: [FormatPlaceholder] {
        var seen = Set<String>()
        return tokens.compactMap { token in
            guard case .placeholder(let placeholder) = token,
                  seen.insert(placeholder.name).inserted else { return nil }
            return placeholder
        }
    }

    /// The placeholder a name resolves to, i.e. the one that owns the port.
    func placeholder(named name: String) -> FormatPlaceholder? {
        placeholders.first { $0.name == name }
    }
}

/// What a format string's literal text may escape: the shared invisible
/// characters — the only way to write one into the single-line Settings field —
/// plus the braces this format claims as syntax.
private let formatStringEscapeSequences: EscapeSequences = [.invisibleCharacters, .braces]

/// Parse a format string into literal text and placeholder occurrences.
///
/// Literals accept `formatStringEscapeSequences`, so an escaped brace is literal
/// text that neither opens nor closes a placeholder.
func parseFormatString(_ formatString: String) -> ParsedFormatString {
    var tokens: [ParsedFormatString.Token] = []
    var literal = ""
    var currentIndex = formatString.startIndex

    func flushLiteral() {
        guard !literal.isEmpty else { return }
        tokens.append(.literal(decodeEscapeSequences(literal, including: formatStringEscapeSequences)))
        literal = ""
    }

    while currentIndex < formatString.endIndex {
        let character = formatString[currentIndex]

        if character == "\\" {
            let escapedCharacterIndex = formatString.index(after: currentIndex)

            guard escapedCharacterIndex < formatString.endIndex else {
                literal.append(character)
                break
            }

            // A backslash shields the character after it from being read as
            // syntax; what the pair stands for is the decoder's business at
            // flush time. So `\{` never opens a placeholder, while `\\{` — a
            // shielded backslash, then a brace — still does.
            literal.append(character)
            literal.append(formatString[escapedCharacterIndex])
            currentIndex = formatString.index(after: escapedCharacterIndex)
            continue
        }

        if character == "{",
           let (placeholder, endIndex) = parsePlaceholder(in: formatString, from: currentIndex) {
            flushLiteral()
            tokens.append(.placeholder(placeholder))
            currentIndex = endIndex
            continue
        }

        literal.append(character)
        currentIndex = formatString.index(after: currentIndex)
    }

    flushLiteral()

    return ParsedFormatString(tokens: tokens)
}

/// Reads one `{name}` / `{name:spec}` starting at `startIndex`, returning it with
/// the index just past its closing brace. Nil for anything else — an unmatched or
/// empty brace is literal text, as it was before placeholders were escapable.
private func parsePlaceholder(
    in formatString: String,
    from startIndex: String.Index
) -> (placeholder: FormatPlaceholder, endIndex: String.Index)? {
    var currentIndex = formatString.index(after: startIndex)

    var name = ""
    while currentIndex < formatString.endIndex {
        let character = formatString[currentIndex]
        guard character.isLetter || character.isNumber || character == "_" else { break }
        name.append(character)
        currentIndex = formatString.index(after: currentIndex)
    }

    guard !name.isEmpty, currentIndex < formatString.endIndex else { return nil }

    var formatSpecifier: String? = nil
    if formatString[currentIndex] == ":" {
        currentIndex = formatString.index(after: currentIndex)

        var specifier = ""
        while currentIndex < formatString.endIndex, formatString[currentIndex] != "}" {
            specifier.append(formatString[currentIndex])
            currentIndex = formatString.index(after: currentIndex)
        }

        guard !specifier.isEmpty else { return nil }
        formatSpecifier = specifier
    }

    guard currentIndex < formatString.endIndex, formatString[currentIndex] == "}" else { return nil }

    return (
        FormatPlaceholder(name: name, formatSpecifier: formatSpecifier),
        formatString.index(after: currentIndex)
    )
}

// MARK: - Settings View

struct StringFormatSettingsView: View {
    @Bindable var model: StringFormatterNode.SettingsModel

    var body: some View {
        VStack(alignment: .leading) {
            Text("Use `{name}` for String, `{name:s}` String, `{name:d}` or `{name:i}` Int, `{name:b}` Bool, `{name:f}` or `{name:.2f}` Float.\n\nExample: `Position: {x:.2f}, {y:.2f}`\n\nEscapes: `\\n`, `\\r`, `\\t`, `\\\\`, and `\\{` `\\}` for literal braces.")

            Spacer()

            TextField("Format String", text: $model.formatString)
                .lineLimit(1)
                .font(.system(size: 10))
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

// MARK: - String Formatter Node

public class StringFormatterNode: Node {
    override public class var name: String { "String Formatter" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Format values into a string using named placeholders. Inverse of String Scanner." }

    override public var displayName: String? { formatString.isEmpty ? nil : formatString }

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

    public fileprivate(set) var formatString: String = "Hello {name}" {
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

    /// Forces one evaluation after a format-string edit, even when no input
    /// changed: a new format produces a different string from the same values,
    /// and a format with no placeholders at all has no input to change.
    private var needsEvaluation = true

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
        AnyView(StringFormatSettingsView(model: _settingsModel))
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
        private weak var node: StringFormatterNode?

        init(node: StringFormatterNode)
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
        let inputsChanged = self.inputPorts().contains { $0.valueDidChange }

        guard inputsChanged || self.needsEvaluation else { return }
        self.needsEvaluation = false

        // Assembled by walking the parse, so a value that happens to look like a
        // placeholder is never substituted into a second time.
        var result = ""

        for token in parsedFormatString.tokens {
            switch token {
            case .literal(let text):
                result += text
            case .placeholder(let placeholder):
                result += formattedValue(named: placeholder.name)
            }
        }

        outputString.send(result)
    }

    /// The value on the port `name` owns, rendered with the specifier that built
    /// that port. Empty when the port is missing or holds no value.
    private func formattedValue(named name: String) -> String {
        guard let placeholder = parsedFormatString.placeholder(named: name) else { return "" }

        switch placeholder.portType {
        case .Float:
            guard let port = self.findPort(named: name) as? NodePort<Float>,
                  let value = port.value else { return "" }
            guard let printfFormat = placeholder.printfFormat else { return String(value) }
            return String(format: printfFormat, value)

        case .Int:
            guard let port = self.findPort(named: name) as? NodePort<Int>,
                  let value = port.value else { return "" }
            guard let printfFormat = placeholder.printfFormat else { return String(value) }
            return String(format: printfFormat, value)

        case .Bool:
            guard let port = self.findPort(named: name) as? NodePort<Bool>,
                  let value = port.value else { return "" }
            return String(value)

        default: // .String
            guard let port = self.findPort(named: name) as? NodePort<String>,
                  let value = port.value else { return "" }
            return value
        }
    }

    // MARK: - Dynamic Port Management

    private func updatePorts() {
        let newParse = parseFormatString(formatString)
        let newPlaceholders = newParse.placeholders

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

        self.parsedFormatString = newParse

        // A format edit reshapes the output even when it reshapes no port, and
        // the renderer skips a node that is not dirty.
        self.needsEvaluation = true
        self.markDirty()
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
