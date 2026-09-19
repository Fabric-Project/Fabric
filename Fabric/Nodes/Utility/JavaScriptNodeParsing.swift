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

    /// The script with its annotations removed, which is what JavaScriptCore runs.
    public let transpiledSource: String

    /// The script as the editor should hold it. Equal to what was parsed, unless
    /// that was the annotated form, in which case it is the same script written
    /// as TypeScript.
    public let canonicalSource: String

    public init(inputs: [JavaScriptNodePortDefinition],
                outputs: [JavaScriptNodePortDefinition],
                transpiledSource: String,
                canonicalSource: String)
    {
        self.inputs = inputs
        self.outputs = outputs
        self.transpiledSource = transpiledSource
        self.canonicalSource = canonicalSource
    }
}

enum JavaScriptNodeParseError: LocalizedError
{
    case blockedSyntax(String)
    case missingMainSignature
    case invalidAnnotation(String)
    case duplicatePortName(String)
    case unsupportedType(String)
    case virtualOutput(String)

    var errorDescription: String?
    {
        switch self
        {
        case .blockedSyntax(let token):
            return "Blocked JavaScript syntax: \(token)"
        case .missingMainSignature:
            return "Expected `function main(name: FabricType, …): { name: FabricType, … }` at the top level."
        case .invalidAnnotation(let annotation):
            return "Invalid port declaration `\(annotation)`."
        case .duplicatePortName(let name):
            return "Port name `\(name)` is declared more than once."
        case .unsupportedType(let type):
            return "Unsupported Fabric type `\(type)`."
        case .virtualOutput(let type):
            return "`\(type)` cannot be an output: there is no way to say what a `FabricValue` is on the way back out."
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

    /// `function main(a: FabricNumber): { b: FabricBool }`, stopping at the last
    /// character of the signature. A return type is optional — a script with no
    /// outputs has none. The whitespace up to the body brace is deliberately
    /// outside the match: it is what separates the signature from the body, and
    /// replacing the match must not take it — see `lineSpanPreserved`.
    private static let typeScriptSignaturePattern =
        #"function\s+main\s*\(([^)]*)\)(?:\s*:\s*(\{[^}]*\}|void))?(?=\s*\{)"#

    /// The annotated form this node started with: `function (__type name) main(__type name)`.
    private static let annotatedSignaturePattern =
        #"function\s*\(([\s\S]*?)\)\s*main\s*\(([\s\S]*?)\)"#

    // MARK: - Types

    /// Fabric's port types under the names a script writes them as. Arrays and
    /// dictionaries are written the way TypeScript writes them — `T[]` and
    /// `Record<string, T>` — so they are composed rather than listed here.
    static let scalarTypeLookup: [String: PortType] = [
        "FabricBool": .Bool,
        "FabricInt": .Int,
        "FabricNumber": .Float,
        "FabricString": .String,
        "FabricVector2": .Vector2,
        "FabricVector3": .Vector3,
        "FabricVector4": .Vector4,
        "FabricColor": .Color,
        "FabricQuaternion": .Quaternion,
        "FabricTransform": .Transform,
        "FabricGeometry": .Geometry,
        "FabricMaterial": .Material,
        "FabricImage": .Image,
        // Only meaningful as a dictionary's value: a dictionary that takes any
        // of the above.
        "FabricValue": .Virtual,
    ]

    /// The annotated form's type names, kept so scripts written against it go on
    /// working. Every one of them has a TypeScript spelling.
    static let annotatedTypeLookup: [String: PortType] = {
        let scalars: [String: PortType] = [
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
        ]

        var lookup = scalars
        lookup["dictionary"] = .Dictionary(valueType: .Virtual)
        for (name, type) in scalars
        {
            lookup["array_\(name)"] = .Array(portType: type)
            lookup["dictionary_\(name)"] = .Dictionary(valueType: type)
        }
        return lookup
    }()

    /// Resolves a TypeScript type, composing `T[]` and `Record<string, T>`.
    static func portType(forTypeScript name: some StringProtocol) -> PortType?
    {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        if trimmed.hasSuffix("[]")
        {
            guard let element = portType(forTypeScript: trimmed.dropLast(2)) else { return nil }
            return .Array(portType: element)
        }

        if trimmed.hasPrefix("Record<"), trimmed.hasSuffix(">")
        {
            let inner = trimmed.dropFirst("Record<".count).dropLast()
            let parts = splitTopLevel(inner)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == "string",
                  let value = portType(forTypeScript: parts[1])
            else { return nil }
            return .Dictionary(valueType: value)
        }

        return scalarTypeLookup[trimmed]
    }

    /// A `FabricValue` anywhere in a type: bare, an array's element, or a
    /// dictionary's value. The bridge has nothing to box such a value back into
    /// — see `virtualOutput` — so it is an input's to declare and no output's.
    static func isVirtual(_ portType: PortType) -> Bool
    {
        switch portType
        {
        case .Virtual: return true
        case .Array(portType: let element): return isVirtual(element)
        case .Dictionary(valueType: let value): return isVirtual(value)
        default: return false
        }
    }

    /// How a port type is written in a signature.
    static func typeScriptName(for portType: PortType) -> String?
    {
        switch portType
        {
        case .Array(portType: let element):
            guard let element = typeScriptName(for: element) else { return nil }
            return "\(element)[]"

        case .Dictionary(valueType: let value):
            guard let value = typeScriptName(for: value) else { return nil }
            return "Record<string, \(value)>"

        default:
            return scalarTypeLookup.first { $0.value == portType }?.key
        }
    }

    // MARK: - Parsing

    static func parse(source: String) throws -> JavaScriptNodeSignature
    {
        for blockedPattern in blockedPatterns
        {
            if source.range(of: blockedPattern.pattern, options: .regularExpression) != nil
            {
                throw JavaScriptNodeParseError.blockedSyntax(blockedPattern.label)
            }
        }

        if let signature = try parseTypeScript(source: source) { return signature }
        if let signature = try parseAnnotated(source: source) { return signature }

        throw JavaScriptNodeParseError.missingMainSignature
    }

    /// The TypeScript form, which is also what a parsed script is written back as.
    private static func parseTypeScript(source: String) throws -> JavaScriptNodeSignature?
    {
        let regex = try NSRegularExpression(pattern: typeScriptSignaturePattern, options: [.dotMatchesLineSeparators])
        let sourceRange = NSRange(source.startIndex..., in: source)

        guard let match = regex.firstMatch(in: source, options: [], range: sourceRange),
              let parameterRange = Range(match.range(at: 1), in: source),
              let fullRange = Range(match.range(at: 0), in: source)
        else { return nil }

        let inputs = try ports(inTypeScriptList: String(source[parameterRange]), direction: .input)

        var outputs: [JavaScriptNodePortDefinition] = []
        if let returnRange = Range(match.range(at: 2), in: source)
        {
            let returnType = String(source[returnRange])
            if returnType != "void"
            {
                outputs = try ports(inTypeScriptList: String(returnType.dropFirst().dropLast()), direction: .output)
            }
        }

        try rejectDuplicates(inputs: inputs, outputs: outputs)

        return JavaScriptNodeSignature(
            inputs: inputs,
            outputs: outputs,
            transpiledSource: source.replacingCharacters(
                in: fullRange,
                with: lineSpanPreserved(runnableSignature(inputs: inputs), replacing: source[fullRange])),
            canonicalSource: source)
    }

    /// The annotated form, rewritten to TypeScript as it is read.
    private static func parseAnnotated(source: String) throws -> JavaScriptNodeSignature?
    {
        let regex = try NSRegularExpression(pattern: annotatedSignaturePattern, options: [.dotMatchesLineSeparators])
        let sourceRange = NSRange(source.startIndex..., in: source)

        guard let match = regex.firstMatch(in: source, options: [], range: sourceRange),
              let outputsRange = Range(match.range(at: 1), in: source),
              let inputsRange = Range(match.range(at: 2), in: source),
              let fullRange = Range(match.range(at: 0), in: source)
        else { return nil }

        let outputs = try ports(inAnnotatedList: String(source[outputsRange]), direction: .output)
        let inputs = try ports(inAnnotatedList: String(source[inputsRange]), direction: .input)

        try rejectDuplicates(inputs: inputs, outputs: outputs)

        let replaced = source[fullRange]

        return JavaScriptNodeSignature(
            inputs: inputs,
            outputs: outputs,
            transpiledSource: source.replacingCharacters(
                in: fullRange,
                with: lineSpanPreserved(runnableSignature(inputs: inputs), replacing: replaced)),
            canonicalSource: source.replacingCharacters(
                in: fullRange,
                with: lineSpanPreserved(typeScriptSignature(inputs: inputs, outputs: outputs), replacing: replaced)))
    }

    // MARK: - Signatures

    /// A signature written to take up as many lines as the one it stands in for.
    /// JavaScriptCore reports an exception at a line of the transpiled source and
    /// the editor marks that line of the script the author wrote, so a signature
    /// rewritten onto fewer lines would report every line below it too high.
    private static func lineSpanPreserved(_ replacement: String, replacing replaced: Substring) -> String
    {
        let shortfall = replaced.filter(\.isNewline).count - replacement.filter(\.isNewline).count
        guard shortfall > 0 else { return replacement }
        return replacement + String(repeating: "\n", count: shortfall)
    }

    /// What JavaScriptCore is given: no types, no return type.
    private static func runnableSignature(inputs: [JavaScriptNodePortDefinition]) -> String
    {
        "function main(\(inputs.map(\.name).joined(separator: ", ")))"
    }

    static func typeScriptSignature(inputs: [JavaScriptNodePortDefinition],
                                    outputs: [JavaScriptNodePortDefinition]) -> String
    {
        func declaration(_ port: JavaScriptNodePortDefinition) -> String
        {
            "\(port.name): \(typeScriptName(for: port.portType) ?? "FabricValue")"
        }

        let parameters = inputs.map(declaration).joined(separator: ", ")
        guard !outputs.isEmpty else { return "function main(\(parameters))" }

        return "function main(\(parameters)): { \(outputs.map(declaration).joined(separator: ", ")) }"
    }

    // MARK: - Port lists

    private static func rejectDuplicates(inputs: [JavaScriptNodePortDefinition],
                                        outputs: [JavaScriptNodePortDefinition]) throws
    {
        let duplicates = Set(inputs.map(\.name)).intersection(outputs.map(\.name))
        if let duplicate = duplicates.first
        {
            throw JavaScriptNodeParseError.duplicatePortName(duplicate)
        }
    }

    /// `name: Type` per entry. A `Record<string, T>` carries a comma of its own,
    /// so entries are split at the commas outside any angle brackets.
    private static func ports(inTypeScriptList list: String,
                              direction: JavaScriptNodePortDefinition.Direction) throws -> [JavaScriptNodePortDefinition]
    {
        var definitions: [JavaScriptNodePortDefinition] = []
        var seenNames = Set<String>()

        for entry in splitTopLevel(Substring(list))
        {
            let part = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty else { continue }

            guard let colon = part.firstIndex(of: ":") else
            {
                throw JavaScriptNodeParseError.invalidAnnotation(part)
            }

            let name = String(part[part.startIndex ..< colon]).trimmingCharacters(in: .whitespaces)
            let typeName = String(part[part.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !typeName.isEmpty else
            {
                throw JavaScriptNodeParseError.invalidAnnotation(part)
            }

            guard let portType = portType(forTypeScript: typeName) else
            {
                throw JavaScriptNodeParseError.unsupportedType(typeName)
            }

            if direction == .output, isVirtual(portType)
            {
                throw JavaScriptNodeParseError.virtualOutput(typeName)
            }

            if seenNames.contains(name) { throw JavaScriptNodeParseError.duplicatePortName(name) }
            seenNames.insert(name)

            definitions.append(JavaScriptNodePortDefinition(direction: direction, name: name, portType: portType))
        }

        return definitions
    }

    /// `__type name` per entry.
    private static func ports(inAnnotatedList list: String,
                              direction: JavaScriptNodePortDefinition.Direction) throws -> [JavaScriptNodePortDefinition]
    {
        let trimmed = list.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var definitions: [JavaScriptNodePortDefinition] = []
        var seenNames = Set<String>()

        for rawPart in trimmed.split(separator: ",", omittingEmptySubsequences: true)
        {
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty else { continue }

            let tokens = part.split(whereSeparator: \.isWhitespace)
            guard tokens.count == 2 else
            {
                throw JavaScriptNodeParseError.invalidAnnotation(part)
            }

            let typeToken = String(tokens[0])
            let nameToken = String(tokens[1])
            guard typeToken.hasPrefix("__") else
            {
                throw JavaScriptNodeParseError.invalidAnnotation(part)
            }

            let normalizedType = String(typeToken.dropFirst(2)).lowercased()
            guard let portType = annotatedTypeLookup[normalizedType] else
            {
                throw JavaScriptNodeParseError.unsupportedType(typeToken)
            }

            if direction == .output, isVirtual(portType)
            {
                throw JavaScriptNodeParseError.virtualOutput(typeToken)
            }

            if seenNames.contains(nameToken) { throw JavaScriptNodeParseError.duplicatePortName(nameToken) }
            seenNames.insert(nameToken)

            definitions.append(JavaScriptNodePortDefinition(direction: direction, name: nameToken, portType: portType))
        }

        return definitions
    }

    /// Splits at commas that are not inside angle brackets.
    private static func splitTopLevel(_ text: some StringProtocol) -> [String]
    {
        var parts: [String] = []
        var current = ""
        var depth = 0

        for character in text
        {
            switch character
            {
            case "<": depth += 1; current.append(character)
            case ">": depth -= 1; current.append(character)
            case "," where depth == 0: parts.append(current); current = ""
            default: current.append(character)
            }
        }

        parts.append(current)
        return parts
    }
}
