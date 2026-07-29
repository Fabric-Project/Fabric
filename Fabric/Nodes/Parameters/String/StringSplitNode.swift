//
//  StringSplitNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI

/// How a String Split node divides its input. Custom is the only mode that takes
/// a Separator inlet, so the mode lives on the Settings picker (a StrategyNode
/// strategy) rather than a wired port.
public enum StringSplitMode: String, NodeStrategyOption, CaseIterable
{
    /// Splits on the exact text supplied by the Separator inlet.
    case custom = "Custom"
    /// Splits on commas.
    case comma = "Comma"
    /// Splits on any whitespace.
    case space = "Space"
    /// Splits on any recognized newline character.
    case newline = "Newline"

    /// One or two sentences shown in the Settings pane to explain the mode.
    public var usageGuidance: String
    {
        switch self
        {
        case .custom:
            return #"Splits on the exact value supplied by the Separator inlet, which understands the \n, \r, \t and \\ escape sequences. Empty and untrimmed components are kept, so joining the result back together reproduces the input."#
        case .comma:
            return "Splits on commas, trims whitespace, and removes empty values. For comma-separated lists written for people to read."
        case .space:
            return "Splits on any whitespace — spaces, tabs and newlines alike — and removes empty values. For splitting prose into words."
        case .newline:
            return "Splits on recognized newline characters, trims whitespace, and removes empty values. For loaded text files, whichever line endings they use."
        }
    }
}

public class StringSplitNode: StrategyNode
{
    override public class var name: String { "String Split" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Split a String into an Array of Strings. Mode (in Settings): a Custom separator, or commas, whitespace, or lines. Inverse of String Join." }

    override public class var strategyOptions: [any NodeStrategyOption] { StringSplitMode.allCases }

    // Title leads with the active mode (StrategyNode default), e.g. "Newline String Split".

    /// The active mode, or nil if the serialized strategy names no known mode.
    public var splitMode: StringSplitMode? { strategyOption() }

    // Settings pane: the strategy picker plus usage guidance for the selected mode.
    override public var settingsSize: SettingsViewSize { .Small }

    override public func settingsView() -> AnyView
    {
        AnyView(StrategyGuidanceView(model: strategySettingsModel) { StringSplitMode(rawValue: $0)?.usageGuidance ?? "" })
    }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputPort", ParameterPort(parameter: StringParameter("String", "", .inputfield, "Input string to split"))),
            ("outputPort", NodePort<ContiguousArray<String>>(name: "Strings", kind: .Outlet, description: "Array of string components")),
        ]
    }

    // Port proxies
    public var inputPort: ParameterPort<String> { port(named: "inputPort") }
    public var outputPort: NodePort<ContiguousArray<String>> { port(named: "outputPort") }
    /// Present only in Custom mode.
    public var inputSeparator: ParameterPort<String>? { findPort(named: "inputSeparator") }

    /// The Separator inlet belongs to Custom alone; the other modes carry their
    /// separator in the mode itself.
    override public func rebuildPorts(forStrategy strategy: String)
    {
        let wantsSeparator = strategy == StringSplitMode.custom.rawValue
        let existingSeparator: ParameterPort<String>? = findPort(named: "inputSeparator")

        switch (wantsSeparator, existingSeparator)
        {
        case (true, nil):
            addDynamicPort(
                ParameterPort(parameter: StringParameter("Separator", ", ", .inputfield, #"Separator string to split on. Supports \n, \r, \t, and \\ escape sequences"#)),
                name: "inputSeparator"
            )
        case (false, let separatorPort?):
            removePort(separatorPort)
        default:
            break
        }

        // The String inlet survives a mode change, so nothing else would mark
        // this node dirty — re-split what's already there the new way.
        if let inputPort: ParameterPort<String> = findPort(named: "inputPort")
        {
            inputPort.valueDidChange = true
            markDirty()
        }
    }

    override public func respondToPull(requestedOutputPort: Port?) -> PullResponse
    {
        guard let inputSeparator else { return .evaluate(pulling: [inputPort]) }
        return .evaluate(pulling: [inputPort, inputSeparator])
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let splitMode else { return }

        let separatorDidChange = inputSeparator?.valueDidChange ?? false
        guard inputPort.valueDidChange || separatorDidChange,
              let string = inputPort.value else
        {
            return
        }

        let separator: String
        if splitMode == .custom
        {
            guard let inputSeparatorValue = inputSeparator?.value else { return }
            separator = inputSeparatorValue
        }
        else
        {
            separator = ""
        }

        outputPort.send(Self.split(string, separator: separator, mode: splitMode))
    }

    static func split(
        _ string: String,
        separator: String,
        mode: StringSplitMode = .custom
    ) -> ContiguousArray<String>
    {
        switch mode
        {
        case .custom:
            return ContiguousArray(
                string.components(separatedBy: decodedSeparator(separator))
            )
        case .comma:
            return splitAndTrim(string.components(separatedBy: ","))
        case .space:
            return ContiguousArray(string.split(whereSeparator: \.isWhitespace).map(String.init))
        case .newline:
            return splitAndTrim(string.components(separatedBy: .newlines))
        }
    }

    private static func splitAndTrim(_ values: [String]) -> ContiguousArray<String>
    {
        ContiguousArray(
            values.compactMap
            {
                value in
                let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedValue.isEmpty ? nil : trimmedValue
            }
        )
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
