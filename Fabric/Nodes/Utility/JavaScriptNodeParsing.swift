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
            return "Expected `function main(name: Type, …): { name: Type, … }` at the top level."
        case .invalidAnnotation(let annotation):
            return "Invalid port declaration `\(annotation)`."
        case .duplicatePortName(let name):
            return "Port name `\(name)` is declared more than once."
        case .unsupportedType(let type):
            return "Unsupported Fabric type `\(type)`."
        case .virtualOutput(let type):
            return "`\(type)` cannot be an output: there is no way to say what a `Value` is on the way back out."
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

    /// `function main(a: Number): { b: Bool }`, stopping at the last
    /// character of the signature. A return type is optional — a script with no
    /// outputs has none. The whitespace up to the body brace is deliberately
    /// outside the match: it is what separates the signature from the body, and
    /// replacing the match must not take it — see `lineSpanPreserved`.
    ///
    /// Anchored to the start of a line, where a top-level declaration is
    /// written. Anything ahead of it on the line — a `//`, an assignment — makes
    /// it commentary about the script rather than the script's own signature,
    /// and the anchor is what keeps commentary from being a match at all rather
    /// than a match to be discarded afterwards. The indent the anchor takes with
    /// it is not part of the signature: see `signatureRange`.
    private static let typeScriptSignaturePattern =
        #"(?m)^[ \t]*function\s+main\s*\(([^)]*)\)(?:\s*:\s*(\{[^}]*\}|void))?(?=\s*\{)"#

    /// The annotated form this node started with: `function (__type name) main(__type name)`,
    /// anchored as `typeScriptSignaturePattern` is.
    private static let annotatedSignaturePattern =
        #"(?m)^[ \t]*function\s*\(([\s\S]*?)\)\s*main\s*\(([\s\S]*?)\)"#

    // MARK: - Types

    /// Fabric's port types under the names a script writes them as. Arrays and
    /// dictionaries are written the way TypeScript writes them — `T[]` and
    /// `Record<string, T>` — so they are composed rather than listed here.
    static let scalarTypeLookup: [String: PortType] = [
        "Bool": .Bool,
        "Int": .Int,
        "Number": .Float,
        "String": .String,
        "Vector2": .Vector2,
        "Vector3": .Vector3,
        "Vector4": .Vector4,
        "Color": .Color,
        "Quaternion": .Quaternion,
        "Transform": .Transform,
        "Geometry": .Geometry,
        "Material": .Material,
        "Image": .Image,
        // Only meaningful as a dictionary's value: a dictionary that takes any
        // of the above.
        "Value": .Virtual,
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

    /// A `Value` anywhere in a type: bare, an array's element, or a
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
        // Worked out once and handed down: every regex below asks the same
        // question of the same source, and the answer does not change between
        // them.
        let outsideComment = positionsOutsideComments(of: source)

        for blockedPattern in blockedPatterns
        {
            let regex = try NSRegularExpression(pattern: blockedPattern.pattern)
            if firstCodeMatch(of: regex, in: source, outsideComment: outsideComment) != nil
            {
                throw JavaScriptNodeParseError.blockedSyntax(blockedPattern.label)
            }
        }

        if let signature = try parseTypeScript(source: source, outsideComment: outsideComment) { return signature }
        if let signature = try parseAnnotated(source: source, outsideComment: outsideComment) { return signature }

        throw JavaScriptNodeParseError.missingMainSignature
    }

    // MARK: - Where the code is

    /// Which of the source's UTF-16 offsets fall outside a comment. A
    /// `function main(…)` written inside one is prose about the script rather
    /// than the script's signature, and the patterns take the first one they are
    /// shown: commenting a signature out while writing its replacement is an
    /// ordinary edit, and it used to hand JavaScriptCore the commented signature
    /// with the real, still-typed one left underneath it.
    ///
    /// Comments only. A string cannot hold a line the signature patterns would
    /// match, because they are anchored to the start of a line and a string's
    /// contents always have its opening quote ahead of them — with one
    /// exception, the template literal, which `insideTemplateLiteral` answers
    /// for. Following string literals here would mean following
    /// regular-expression literals too, since telling a delimiting `/` from a
    /// dividing one needs the parse this node does without, and a quote inside a
    /// regex would otherwise open a string the script never wrote. Comments ask
    /// none of that: neither form quotes or escapes anything.
    private static func positionsOutsideComments(of source: String) -> [Bool]
    {
        let units = Array(source.utf16)
        var outsideComment = [Bool](repeating: false, count: units.count)

        let slash = UInt16(UInt8(ascii: "/"))
        let star = UInt16(UInt8(ascii: "*"))
        let newline = UInt16(UInt8(ascii: "\n"))

        var index = 0
        while index < units.count
        {
            let unit = units[index]

            if unit == slash, index + 1 < units.count, units[index + 1] == slash
            {
                while index < units.count, units[index] != newline { index += 1 }
                continue
            }

            if unit == slash, index + 1 < units.count, units[index + 1] == star
            {
                index += 2
                while index + 1 < units.count, !(units[index] == star && units[index + 1] == slash)
                {
                    index += 1
                }
                index = min(index + 2, units.count)
                continue
            }

            outsideComment[index] = true
            index += 1
        }

        return outsideComment
    }

    /// Whether the offset stands inside a template literal. It is the one string
    /// that spans lines, so the one that can hold a line the anchored patterns
    /// would otherwise match.
    ///
    /// A backtick opens one only where another closes it. The scan does not read
    /// regular-expression literals, so a lone backtick inside one would
    /// otherwise put every line below it inside a template the script never
    /// wrote. Two of them still pair with each other, which is as far as this
    /// goes without the parse.
    private static func insideTemplateLiteral(_ source: String,
                                              at offset: Int,
                                              outsideComment: [Bool]) -> Bool
    {
        let units = Array(source.utf16)
        let backtick = UInt16(UInt8(ascii: "`"))
        let backslash = UInt16(UInt8(ascii: "\\"))

        func nextBacktick(from start: Int) -> Int?
        {
            var index = start
            while index < units.count
            {
                if units[index] == backslash { index += 2; continue }
                if units[index] == backtick, outsideComment[index] { return index }
                index += 1
            }
            return nil
        }

        var index = 0
        while let open = nextBacktick(from: index)
        {
            if open >= offset { return false }
            guard let close = nextBacktick(from: open + 1) else { return false }
            if offset < close { return true }
            index = close + 1
        }

        return false
    }

    /// The first match the source actually says, rather than the first one it
    /// contains: the first beginning outside a comment and outside a template
    /// literal.
    private static func firstCodeMatch(of regex: NSRegularExpression,
                                       in source: String,
                                       outsideComment: [Bool]) -> NSTextCheckingResult?
    {
        let sourceRange = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, options: [], range: sourceRange).first { match in
            let start = contentStart(of: match, in: source)
            return start < outsideComment.count
                && outsideComment[start]
                && !insideTemplateLiteral(source, at: start, outsideComment: outsideComment)
        }
    }

    /// Where a match's own text begins, past any whitespace its anchor took with
    /// it. That is the offset the two tests above are asking about, the indent
    /// ahead of a signature being neither its comment nor its own.
    private static func contentStart(of match: NSTextCheckingResult, in source: String) -> Int
    {
        let units = Array(source.utf16)
        let whitespace: Set<UInt16> = [UInt16(UInt8(ascii: " ")),
                                       UInt16(UInt8(ascii: "\t")),
                                       UInt16(UInt8(ascii: "\n")),
                                       UInt16(UInt8(ascii: "\r"))]

        var start = match.range.location
        while start < units.count, whitespace.contains(units[start]) { start += 1 }
        return start
    }

    /// The signature a match stands for, without the indent the anchor took with
    /// it. This is the span a rewrite replaces, and taking the indent too would
    /// move the signature to the start of its line.
    private static func signatureRange(of match: NSTextCheckingResult,
                                       in source: String) -> Range<String.Index>?
    {
        let start = contentStart(of: match, in: source)
        let end = match.range.location + match.range.length
        guard start <= end else { return nil }
        return Range(NSRange(location: start, length: end - start), in: source)
    }

    /// The TypeScript form, which is also what a parsed script is written back as.
    private static func parseTypeScript(source: String, outsideComment: [Bool]) throws -> JavaScriptNodeSignature?
    {
        let regex = try NSRegularExpression(pattern: typeScriptSignaturePattern, options: [.dotMatchesLineSeparators])

        guard let match = firstCodeMatch(of: regex, in: source, outsideComment: outsideComment),
              let parameterRange = Range(match.range(at: 1), in: source),
              let fullRange = signatureRange(of: match, in: source)
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
    private static func parseAnnotated(source: String, outsideComment: [Bool]) throws -> JavaScriptNodeSignature?
    {
        let regex = try NSRegularExpression(pattern: annotatedSignaturePattern, options: [.dotMatchesLineSeparators])

        guard let match = firstCodeMatch(of: regex, in: source, outsideComment: outsideComment),
              let outputsRange = Range(match.range(at: 1), in: source),
              let inputsRange = Range(match.range(at: 2), in: source),
              let fullRange = signatureRange(of: match, in: source)
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
            "\(port.name): \(typeScriptName(for: port.portType) ?? "Value")"
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
