//
//  StringSplitNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI

public enum StringSplitMode: String, Codable, CaseIterable, Sendable
{
    case exactSeparator = "Exact Separator"
    case words = "Words"
    case commas = "Commas"
    case lines = "Lines"

    var description: String
    {
        switch self
        {
        case .exactSeparator:
            "Splits on the exact value supplied by the Separator inlet."
        case .words:
            "Splits on any whitespace."
        case .commas:
            "Splits on commas, trims whitespace, and removes empty values."
        case .lines:
            "Splits on recognized newline characters, trims whitespace, and removes empty values."
        }
    }
}

private struct StringSplitSettingsView: View
{
    let node: StringSplitNode
    @State private var splitMode: StringSplitMode

    init(node: StringSplitNode)
    {
        self.node = node
        _splitMode = State(initialValue: node.splitMode)
    }

    var body: some View
    {
        VStack(alignment: .leading)
        {
            Picker("Split Mode", selection: $splitMode)
            {
                ForEach(StringSplitMode.allCases, id: \.self)
                {
                    splitMode in
                    Text(splitMode.rawValue).tag(splitMode)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .onChange(of: splitMode)
            {
                _, newSplitMode in
                node.splitMode = newSplitMode
            }

            Text(splitMode.description)
                .foregroundStyle(.secondary)
        }
    }
}

public class StringSplitNode: Node {
    override public class var name: String { "String Split" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Split a String into an Array of Strings using an exact separator, whitespace, commas, or lines. Inverse of String Join." }

    // MARK: - Settings

    public fileprivate(set) var splitMode: StringSplitMode
    {
        didSet
        {
            guard splitMode != oldValue else { return }
            inputPort.valueDidChange = true
            markDirty()
        }
    }

    private enum CodingKeys: String, CodingKey
    {
        case splitMode
    }

    public required init(context: Context)
    {
        splitMode = .exactSeparator
        super.init(context: context)
    }

    public init(context: Context, splitMode: StringSplitMode)
    {
        self.splitMode = splitMode
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        splitMode = try container.decodeIfPresent(StringSplitMode.self, forKey: .splitMode)
            ?? .exactSeparator
        try super.init(from: decoder)
    }

    public override func encode(to encoder: any Encoder) throws
    {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(splitMode, forKey: .splitMode)
    }

    override public func providesSettingsView() -> Bool { true }

    override public var settingsSize: SettingsViewSize { .Small }

    override public func settingsView() -> AnyView
    {
        AnyView(StringSplitSettingsView(node: self))
    }
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports + [
            ("inputPort", ParameterPort(parameter: StringParameter("String", "", .inputfield, "Input string to split"))),
            ("inputSeparator", ParameterPort(parameter: StringParameter("Separator", ", ", .inputfield, #"Separator string to split on. Supports \n, \r, \t, and \\ escape sequences"#))),
            ("outputPort", NodePort<ContiguousArray<String>>(name: "Strings", kind: .Outlet, description: "Array of string components")),
        ]
    }
    
    // Port proxies
    public var inputPort: ParameterPort<String> { port(named: "inputPort") }
    public var inputSeparator: ParameterPort<String> { port(named: "inputSeparator") }
    public var outputPort: NodePort<ContiguousArray<String>> { port(named: "outputPort") }

    override public func respondToPull(requestedOutputPort: Port?) -> PullResponse
    {
        switch splitMode
        {
        case .exactSeparator:
            return .evaluate(pulling: [inputPort, inputSeparator])
        case .words, .commas, .lines:
            return .evaluate(pulling: [inputPort])
        }
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let separatorDidChange = splitMode == .exactSeparator && inputSeparator.valueDidChange
        guard inputPort.valueDidChange || separatorDidChange,
              let string = inputPort.value else
        {
            return
        }

        let separator: String
        if splitMode == .exactSeparator
        {
            guard let inputSeparatorValue = inputSeparator.value else { return }
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
        mode: StringSplitMode = .exactSeparator
    ) -> ContiguousArray<String>
    {
        switch mode
        {
        case .exactSeparator:
            return ContiguousArray(
                string.components(separatedBy: decodedSeparator(separator))
            )
        case .words:
            return ContiguousArray(string.split(whereSeparator: \.isWhitespace).map(String.init))
        case .commas:
            return splitAndTrim(string.components(separatedBy: ","))
        case .lines:
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
