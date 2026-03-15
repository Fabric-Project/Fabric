//
//  JavaScriptNodeParsing.swift
//  Fabric
//
//  Created by Codex on 3/14/26.
//

import Foundation

public struct JavaScriptNodePortDefinition: Hashable
{
    public enum Direction: Hashable
    {
        case input
        case output
    }

    public let direction: Direction
    public let name: String
    public let portType: PortType

    public init(direction: Direction, name: String, portType: PortType)
    {
        self.direction = direction
        self.name = name
        self.portType = portType
    }

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(direction)
        hasher.combine(name)
        hasher.combine(portType.rawValue)
    }
}

public struct JavaScriptNodeSignature: Hashable
{
    public let inputs: [JavaScriptNodePortDefinition]
    public let outputs: [JavaScriptNodePortDefinition]
    public let transpiledSource: String

    public init(inputs: [JavaScriptNodePortDefinition], outputs: [JavaScriptNodePortDefinition], transpiledSource: String)
    {
        self.inputs = inputs
        self.outputs = outputs
        self.transpiledSource = transpiledSource
    }
}

enum JavaScriptNodeParseError: LocalizedError
{
    case blockedSyntax(String)
    case missingMainSignature
    case invalidAnnotation(String)
    case duplicatePortName(String)
    case unsupportedType(String)
    case shaderUnsupported

    var errorDescription: String?
    {
        switch self
        {
        case .blockedSyntax(let token):
            return "Blocked JavaScript syntax: \(token)"
        case .missingMainSignature:
            return "Expected `function (<outputs>) main(<inputs>)` at the top level."
        case .invalidAnnotation(let annotation):
            return "Invalid port annotation `\(annotation)`."
        case .duplicatePortName(let name):
            return "Port name `\(name)` is declared more than once."
        case .unsupportedType(let type):
            return "Unsupported Fabric JavaScript type `\(type)`."
        case .shaderUnsupported:
            return "Shader ports are not supported in the JavaScript node."
        }
    }
}

enum JavaScriptNodeSourceParser
{
    private static let blockedPatterns: [(label: String, pattern: String)] = [
        ("import", #"(?m)^\s*import\b"#),
        ("export", #"(?m)^\s*export\b"#),
        ("require", #"\brequire\s*\("#),
        ("dynamic import", #"\bimport\s*\("#),
    ]

    private static let signaturePattern = #"function\s*\(([\s\S]*?)\)\s*main\s*\(([\s\S]*?)\)"#

    static let typeLookup: [String: PortType] = [
        "bool": .Bool,
        "int": .Int,
        "number": .Float,
        "float": .Float,
        "string": .String,
        "vector2": .Vector2,
        "vector3": .Vector3,
        "vector4": .Vector4,
        "color": .Color,
        "quaternion": .Quaternion,
        "transform": .Transform,
        "geometry": .Geometry,
        "material": .Material,
        "image": .Image,
        "array_bool": .Array(portType: .Bool),
        "array_int": .Array(portType: .Int),
        "array_number": .Array(portType: .Float),
        "array_float": .Array(portType: .Float),
        "array_string": .Array(portType: .String),
        "array_vector2": .Array(portType: .Vector2),
        "array_vector3": .Array(portType: .Vector3),
        "array_vector4": .Array(portType: .Vector4),
        "array_color": .Array(portType: .Color),
        "array_quaternion": .Array(portType: .Quaternion),
        "array_transform": .Array(portType: .Transform),
        "array_geometry": .Array(portType: .Geometry),
        "array_material": .Array(portType: .Material),
        "array_image": .Array(portType: .Image),
    ]

    static func parse(source: String) throws -> JavaScriptNodeSignature
    {
        for blockedPattern in blockedPatterns {
            if source.range(of: blockedPattern.pattern, options: .regularExpression) != nil {
                throw JavaScriptNodeParseError.blockedSyntax(blockedPattern.label)
            }
        }

        let regex = try NSRegularExpression(pattern: signaturePattern, options: [.dotMatchesLineSeparators])
        let sourceRange = NSRange(source.startIndex..., in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: sourceRange),
              let outputsRange = Range(match.range(at: 1), in: source),
              let inputsRange = Range(match.range(at: 2), in: source),
              let fullRange = Range(match.range(at: 0), in: source) else {
            throw JavaScriptNodeParseError.missingMainSignature
        }

        let outputs = try parse(portList: String(source[outputsRange]), direction: .output)
        let inputs = try parse(portList: String(source[inputsRange]), direction: .input)

        let duplicateNames = Set(inputs.map(\.name)).intersection(outputs.map(\.name))
        if let duplicateName = duplicateNames.first {
            throw JavaScriptNodeParseError.duplicatePortName(duplicateName)
        }

        let transpiledMain = "function main(\(inputs.map(\.name).joined(separator: ", ")))"
        let transpiledSource = source.replacingCharacters(in: fullRange, with: transpiledMain)

        return JavaScriptNodeSignature(inputs: inputs,
                                       outputs: outputs,
                                       transpiledSource: transpiledSource)
    }

    private static func parse(portList: String,
                              direction: JavaScriptNodePortDefinition.Direction) throws -> [JavaScriptNodePortDefinition]
    {
        let trimmed = portList.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: true)
        var definitions: [JavaScriptNodePortDefinition] = []
        var seenNames = Set<String>()

        for rawPart in parts {
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard part.isEmpty == false else { continue }

            let tokens = part.split(whereSeparator: \.isWhitespace)
            guard tokens.count == 2 else {
                throw JavaScriptNodeParseError.invalidAnnotation(part)
            }

            let typeToken = String(tokens[0])
            let nameToken = String(tokens[1])
            guard typeToken.hasPrefix("__") else {
                throw JavaScriptNodeParseError.invalidAnnotation(part)
            }

            let normalizedType = String(typeToken.dropFirst(2)).lowercased()
            guard let portType = typeLookup[normalizedType] else {
                throw JavaScriptNodeParseError.unsupportedType(typeToken)
            }

            if portType == .Shader || portType == .Array(portType: .Shader) {
                throw JavaScriptNodeParseError.shaderUnsupported
            }

            if seenNames.contains(nameToken) {
                throw JavaScriptNodeParseError.duplicatePortName(nameToken)
            }

            seenNames.insert(nameToken)
            definitions.append(JavaScriptNodePortDefinition(direction: direction,
                                                            name: nameToken,
                                                            portType: portType))
        }

        return definitions
    }
}
