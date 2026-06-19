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
    override public class var nodeDescription: String { "Wrap a String by inserting newlines at word boundaries" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputPort", NodePort<String>(name: "String", kind: .Inlet, description: "Input string to wrap")),
            ("inputMode", ParameterPort(parameter: StringParameter("Mode", "Characters", WrapMode.allCases.map(\.rawValue), .dropdown, "Wrap criterion: Characters, Words, or Aspect"))),
            ("inputLimit", ParameterPort(parameter: IntParameter("Limit", 40, 1, 10000, .inputfield, "Character or word count per line"))),
            ("inputAspect", ParameterPort(parameter: FloatParameter("Aspect", 4.0, 0.01, 100.0, .inputfield, "Target aspect ratio (characters across / lines down)"))),
            ("outputPort", NodePort<String>(name: "String", kind: .Outlet, description: "String with newlines inserted at word boundaries")),
        ]
    }

    // Port proxies
    public var inputPort: NodePort<String> { port(named: "inputPort") }
    public var inputMode: ParameterPort<String> { port(named: "inputMode") }
    public var inputLimit: ParameterPort<Int> { port(named: "inputLimit") }
    public var inputAspect: ParameterPort<Float> { port(named: "inputAspect") }
    public var outputPort: NodePort<String> { port(named: "outputPort") }

    private var mode = WrapMode.Characters

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
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

        let charLimit: Int
        switch mode {
        case .Characters:
            charLimit = max(1, inputLimit.value ?? 40)
        case .Words:
            charLimit = wordCountToCharLimit(words: words, wordLimit: max(1, inputLimit.value ?? 10))
        case .Aspect:
            charLimit = aspectToCharLimit(words: words, aspect: inputAspect.value ?? 4.0)
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
                let candidate = currentLine + " " + word
                if currentLine.count >= charLimit {
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

    /// Convert a word-count limit to a character limit by measuring the average word length.
    private func wordCountToCharLimit(words: [String], wordLimit: Int) -> Int {
        let totalChars = words.reduce(0) { $0 + $1.count }
        let avgWordLen = Double(totalChars) / Double(words.count)
        // word + space
        return max(1, Int((avgWordLen + 1) * Double(wordLimit)))
    }

    /// Calculate a character-per-line limit that fits the text within the target aspect ratio.
    /// aspect = characters across / lines down, so chars = sqrt(totalChars * aspect).
    private func aspectToCharLimit(words: [String], aspect: Float) -> Int {
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
