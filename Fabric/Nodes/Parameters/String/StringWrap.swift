//
//  StringWrap.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class StringWrapNode: Node {
    override public class var name: String { "String Wrap" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Wrap at word boundaries using: Characters – line length in characters; Words – number of words per line; Aspect – overall aspect ratio (characters across vs. lines down" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputPort", ParameterPort(parameter: StringParameter("String", "", .inputfield, "Input string to wrap"))),
            ("inputMode", ParameterPort(parameter: StringParameter("Mode", "Characters", WrapMode.allCases.map(\.rawValue), .dropdown, "Wrap criterion: Characters, Words, or Aspect"))),
            ("inputLimit", ParameterPort(parameter: IntParameter("Limit", 40, 1, 10000, .inputfield, "Character or word count per line"))),
            ("inputAspect", ParameterPort(parameter: FloatParameter("Aspect", 4.0, 0.01, 100.0, .inputfield, "Target aspect ratio (characters across / lines down)"))),
            ("outputPort", NodePort<String>(name: "String", kind: .Outlet, description: "String with newlines inserted at word boundaries")),
        ]
    }

    // Port proxies
    public var inputPort: ParameterPort<String> { port(named: "inputPort") }
    public var inputMode: ParameterPort<String> { port(named: "inputMode") }
    public var inputLimit: ParameterPort<Int> { port(named: "inputLimit") }
    public var inputAspect: ParameterPort<Float> { port(named: "inputAspect") }
    public var outputPort: NodePort<String> { port(named: "outputPort") }

    private var mode = WrapMode.Characters

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if inputMode.valueDidChange,
           let param = inputMode.value,
           let newMode = WrapMode(rawValue: param) {
            mode = newMode
        }

        let anyChanged = inputPort.valueDidChange || inputMode.valueDidChange
                         || inputLimit.valueDidChange || inputAspect.valueDidChange
        guard anyChanged, let string = inputPort.value else { return }

        let words = string.split(omittingEmptySubsequences: false, whereSeparator: \.isWhitespace)
                          .map(String.init)
        guard !words.isEmpty else {
            outputPort.send("")
            return
        }

        let wrapped: String
        switch mode {
        case .Characters:
            wrapped = Self.wrapToCharLimit(words, charLimit: max(1, inputLimit.value ?? 40))
        case .Words:
            wrapped = Self.wrapToWordLimit(words, wordLimit: max(1, inputLimit.value ?? 10))
        case .Aspect:
            wrapped = Self.wrapToCharLimit(words, charLimit: Self.aspectToCharLimit(words: words, aspect: inputAspect.value ?? 4.0))
        }

        outputPort.send(wrapped)
    }

    /// Greedily fill each line with whole words, breaking before the word that would
    /// take the line past `charLimit`. A word longer than the limit takes a line of
    /// its own and overruns it — the alternative is splitting mid-word.
    static func wrapToCharLimit(_ words: [String], charLimit: Int) -> String {
        var lines: [String] = []
        var currentLine = ""

        for word in words {
            if currentLine.isEmpty {
                currentLine = word
            } else {
                let candidate = currentLine + " " + word
                if candidate.count > charLimit {
                    lines.append(currentLine)
                    currentLine = word
                } else {
                    currentLine = candidate
                }
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        return lines.joined(separator: "\n")
    }

    /// Break every `wordLimit` words. Counts words rather than deriving a character
    /// limit from them, so the requested count is exact whatever the word lengths.
    /// `wordLimit` must be at least 1.
    static func wrapToWordLimit(_ words: [String], wordLimit: Int) -> String {
        stride(from: 0, to: words.count, by: wordLimit).map { start in
            words[start ..< min(start + wordLimit, words.count)].joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    /// Calculate a character-per-line limit that fits the text within the target aspect ratio.
    /// aspect = characters across / lines down, so chars = sqrt(totalChars * aspect).
    static func aspectToCharLimit(words: [String], aspect: Float) -> Int {
        let totalChars = words.reduce(0) { $0 + $1.count } + max(0, words.count - 1) // include spaces
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
