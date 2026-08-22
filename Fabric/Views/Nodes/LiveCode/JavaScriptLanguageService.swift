//
//  JavaScriptLanguageService.swift
//  Fabric
//
//  Created by Codex on 3/14/26.
//

import Combine
import Foundation
import LanguageSupport
import SwiftUI

private struct JavaScriptCompletionEntry
{
    enum Kind: String
    {
        case keyword
        case builtin
        case global
        case input
        case output
        case property
    }

    let label: String
    let insertText: String
    let documentation: String
    let kind: Kind
    let priority: Int
}

final class JavaScriptLanguageService: LanguageService
{
    var isOpen: Bool = false
    let events = PassthroughSubject<LanguageServiceEvent, Never>()
    let diagnostics = CurrentValueSubject<Set<TextLocated<Message>>, Never>([])
    let completionTriggerCharacters = CurrentValueSubject<[Character], Never>(["."])
    let extraActions = CurrentValueSubject<[ExtraAction], Never>([])

    private var documentText: String = ""
    private var locationService: LocationService?
    private var signature: JavaScriptNodeSignature?

    private static let identifierCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$"))

    private static let keywordEntries: [JavaScriptCompletionEntry] = [
        .init(label: "function", insertText: "function", documentation: "Declare a JavaScript function.", kind: .keyword, priority: 300),
        .init(label: "return", insertText: "return", documentation: "Return a value from the current function.", kind: .keyword, priority: 300),
        .init(label: "const", insertText: "const", documentation: "Declare an immutable binding.", kind: .keyword, priority: 300),
        .init(label: "let", insertText: "let", documentation: "Declare a mutable binding.", kind: .keyword, priority: 300),
        .init(label: "if", insertText: "if", documentation: "Conditional branch.", kind: .keyword, priority: 300),
        .init(label: "else", insertText: "else", documentation: "Fallback branch.", kind: .keyword, priority: 300),
        .init(label: "for", insertText: "for", documentation: "Loop over a range or collection.", kind: .keyword, priority: 300),
        .init(label: "while", insertText: "while", documentation: "Loop while a condition is true.", kind: .keyword, priority: 300),
        .init(label: "true", insertText: "true", documentation: "Boolean literal.", kind: .keyword, priority: 300),
        .init(label: "false", insertText: "false", documentation: "Boolean literal.", kind: .keyword, priority: 300),
        .init(label: "null", insertText: "null", documentation: "Null literal.", kind: .keyword, priority: 300),
    ]

    private static let builtinEntries: [JavaScriptCompletionEntry] = [
        .init(label: "Math", insertText: "Math", documentation: "Built-in math utilities.", kind: .builtin, priority: 250),
        .init(label: "Object", insertText: "Object", documentation: "Built-in object utilities.", kind: .builtin, priority: 250),
        .init(label: "Array", insertText: "Array", documentation: "Built-in array utilities.", kind: .builtin, priority: 250),
        .init(label: "JSON", insertText: "JSON", documentation: "Built-in JSON parser and serializer.", kind: .builtin, priority: 250),
        .init(label: "Number", insertText: "Number", documentation: "Built-in number utilities.", kind: .builtin, priority: 250),
        .init(label: "String", insertText: "String", documentation: "Built-in string utilities.", kind: .builtin, priority: 250),
        .init(label: "Date", insertText: "Date", documentation: "Built-in date utilities.", kind: .builtin, priority: 250),
        .init(label: "parseFloat", insertText: "parseFloat", documentation: "Parse a floating-point number from text.", kind: .builtin, priority: 240),
        .init(label: "parseInt", insertText: "parseInt", documentation: "Parse an integer from text.", kind: .builtin, priority: 240),
        .init(label: "isFinite", insertText: "isFinite", documentation: "Return whether a value is a finite number.", kind: .builtin, priority: 240),
        .init(label: "isNaN", insertText: "isNaN", documentation: "Return whether a value is NaN.", kind: .builtin, priority: 240),
        .init(label: "console", insertText: "console", documentation: "Fabric console bridge.", kind: .global, priority: 260),
        .init(label: "context", insertText: "context", documentation: "Fabric execution timing and iteration context.", kind: .global, priority: 270),
    ]

    private static let contextEntries: [JavaScriptCompletionEntry] = [
        .init(label: "time", insertText: "time", documentation: "Relative execution time.", kind: .property, priority: 500),
        .init(label: "deltaTime", insertText: "deltaTime", documentation: "Elapsed time since the previous execution.", kind: .property, priority: 500),
        .init(label: "displayTime", insertText: "displayTime", documentation: "Predicted display time for the current frame.", kind: .property, priority: 500),
        .init(label: "systemTime", insertText: "systemTime", documentation: "System absolute execution time.", kind: .property, priority: 500),
        .init(label: "frameNumber", insertText: "frameNumber", documentation: "Current graph frame number.", kind: .property, priority: 500),
        .init(label: "iterationIndex", insertText: "iterationIndex", documentation: "Current iterator index when running inside an iterator.", kind: .property, priority: 500),
        .init(label: "iterationCount", insertText: "iterationCount", documentation: "Total iteration count when running inside an iterator.", kind: .property, priority: 500),
    ]

    private static let consoleEntries: [JavaScriptCompletionEntry] = [
        .init(label: "log", insertText: "log", documentation: "Print a value to the Fabric log.", kind: .property, priority: 500),
    ]

    private static let mathEntries: [JavaScriptCompletionEntry] = [
        .init(label: "abs", insertText: "abs", documentation: "Return the absolute value of a number.", kind: .property, priority: 500),
        .init(label: "acos", insertText: "acos", documentation: "Return the arccosine of a number.", kind: .property, priority: 500),
        .init(label: "asin", insertText: "asin", documentation: "Return the arcsine of a number.", kind: .property, priority: 500),
        .init(label: "atan", insertText: "atan", documentation: "Return the arctangent of a number.", kind: .property, priority: 500),
        .init(label: "atan2", insertText: "atan2", documentation: "Return the angle from the X axis to a point.", kind: .property, priority: 500),
        .init(label: "ceil", insertText: "ceil", documentation: "Round a number up.", kind: .property, priority: 500),
        .init(label: "cos", insertText: "cos", documentation: "Return the cosine of an angle in radians.", kind: .property, priority: 500),
        .init(label: "exp", insertText: "exp", documentation: "Return Euler's number raised to a power.", kind: .property, priority: 500),
        .init(label: "floor", insertText: "floor", documentation: "Round a number down.", kind: .property, priority: 500),
        .init(label: "log", insertText: "log", documentation: "Return the natural logarithm of a number.", kind: .property, priority: 500),
        .init(label: "max", insertText: "max", documentation: "Return the largest of the provided numbers.", kind: .property, priority: 500),
        .init(label: "min", insertText: "min", documentation: "Return the smallest of the provided numbers.", kind: .property, priority: 500),
        .init(label: "PI", insertText: "PI", documentation: "Ratio of a circle's circumference to its diameter.", kind: .property, priority: 500),
        .init(label: "pow", insertText: "pow", documentation: "Raise a base to an exponent.", kind: .property, priority: 500),
        .init(label: "random", insertText: "random", documentation: "Return a pseudo-random number between 0 and 1.", kind: .property, priority: 500),
        .init(label: "round", insertText: "round", documentation: "Round a number to the nearest integer.", kind: .property, priority: 500),
        .init(label: "sign", insertText: "sign", documentation: "Return the sign of a number.", kind: .property, priority: 500),
        .init(label: "sin", insertText: "sin", documentation: "Return the sine of an angle in radians.", kind: .property, priority: 500),
        .init(label: "sqrt", insertText: "sqrt", documentation: "Return the square root of a number.", kind: .property, priority: 500),
        .init(label: "tan", insertText: "tan", documentation: "Return the tangent of an angle in radians.", kind: .property, priority: 500),
        .init(label: "trunc", insertText: "trunc", documentation: "Remove the fractional digits of a number.", kind: .property, priority: 500),
    ]

    private static let objectEntries: [JavaScriptCompletionEntry] = [
        .init(label: "assign", insertText: "assign", documentation: "Copy properties from source objects into a target object.", kind: .property, priority: 500),
        .init(label: "create", insertText: "create", documentation: "Create a new object with the specified prototype.", kind: .property, priority: 500),
        .init(label: "entries", insertText: "entries", documentation: "Return an array of key/value pairs for an object.", kind: .property, priority: 500),
        .init(label: "freeze", insertText: "freeze", documentation: "Prevent an object from being mutated.", kind: .property, priority: 500),
        .init(label: "fromEntries", insertText: "fromEntries", documentation: "Create an object from key/value pairs.", kind: .property, priority: 500),
        .init(label: "hasOwn", insertText: "hasOwn", documentation: "Return whether an object owns a property.", kind: .property, priority: 500),
        .init(label: "is", insertText: "is", documentation: "Compare two values using SameValue semantics.", kind: .property, priority: 500),
        .init(label: "keys", insertText: "keys", documentation: "Return the enumerable property names of an object.", kind: .property, priority: 500),
        .init(label: "seal", insertText: "seal", documentation: "Prevent adding or removing object properties.", kind: .property, priority: 500),
        .init(label: "values", insertText: "values", documentation: "Return the enumerable property values of an object.", kind: .property, priority: 500),
    ]

    private static let arrayEntries: [JavaScriptCompletionEntry] = [
        .init(label: "from", insertText: "from", documentation: "Create an array from an iterable or array-like value.", kind: .property, priority: 500),
        .init(label: "isArray", insertText: "isArray", documentation: "Return whether a value is an array.", kind: .property, priority: 500),
        .init(label: "of", insertText: "of", documentation: "Create an array from the provided arguments.", kind: .property, priority: 500),
    ]

    private static let jsonEntries: [JavaScriptCompletionEntry] = [
        .init(label: "parse", insertText: "parse", documentation: "Parse a JSON string into a JavaScript value.", kind: .property, priority: 500),
        .init(label: "stringify", insertText: "stringify", documentation: "Serialize a JavaScript value as JSON.", kind: .property, priority: 500),
    ]

    private static let numberEntries: [JavaScriptCompletionEntry] = [
        .init(label: "EPSILON", insertText: "EPSILON", documentation: "Smallest interval between two representable numbers greater than 1.", kind: .property, priority: 500),
        .init(label: "MAX_SAFE_INTEGER", insertText: "MAX_SAFE_INTEGER", documentation: "Largest safely representable integer.", kind: .property, priority: 500),
        .init(label: "MAX_VALUE", insertText: "MAX_VALUE", documentation: "Largest representable numeric value.", kind: .property, priority: 500),
        .init(label: "MIN_SAFE_INTEGER", insertText: "MIN_SAFE_INTEGER", documentation: "Smallest safely representable integer.", kind: .property, priority: 500),
        .init(label: "MIN_VALUE", insertText: "MIN_VALUE", documentation: "Smallest positive representable numeric value.", kind: .property, priority: 500),
        .init(label: "NaN", insertText: "NaN", documentation: "Not-a-Number sentinel.", kind: .property, priority: 500),
        .init(label: "NEGATIVE_INFINITY", insertText: "NEGATIVE_INFINITY", documentation: "Negative infinity constant.", kind: .property, priority: 500),
        .init(label: "POSITIVE_INFINITY", insertText: "POSITIVE_INFINITY", documentation: "Positive infinity constant.", kind: .property, priority: 500),
        .init(label: "isFinite", insertText: "isFinite", documentation: "Return whether a value is a finite number.", kind: .property, priority: 500),
        .init(label: "isInteger", insertText: "isInteger", documentation: "Return whether a value is an integer.", kind: .property, priority: 500),
        .init(label: "isNaN", insertText: "isNaN", documentation: "Return whether a value is NaN.", kind: .property, priority: 500),
        .init(label: "isSafeInteger", insertText: "isSafeInteger", documentation: "Return whether a value is a safe integer.", kind: .property, priority: 500),
        .init(label: "parseFloat", insertText: "parseFloat", documentation: "Parse a floating-point number from text.", kind: .property, priority: 500),
        .init(label: "parseInt", insertText: "parseInt", documentation: "Parse an integer from text.", kind: .property, priority: 500),
    ]

    private static let stringEntries: [JavaScriptCompletionEntry] = [
        .init(label: "fromCharCode", insertText: "fromCharCode", documentation: "Create a string from UTF-16 code units.", kind: .property, priority: 500),
        .init(label: "fromCodePoint", insertText: "fromCodePoint", documentation: "Create a string from Unicode code points.", kind: .property, priority: 500),
        .init(label: "raw", insertText: "raw", documentation: "Return the raw string value of a template literal.", kind: .property, priority: 500),
    ]

    private static let dateEntries: [JavaScriptCompletionEntry] = [
        .init(label: "now", insertText: "now", documentation: "Return the current timestamp in milliseconds.", kind: .property, priority: 500),
        .init(label: "parse", insertText: "parse", documentation: "Parse a date string into a timestamp.", kind: .property, priority: 500),
        .init(label: "UTC", insertText: "UTC", documentation: "Create a UTC timestamp from date components.", kind: .property, priority: 500),
    ]

    private static let imageEntries: [JavaScriptCompletionEntry] = [
        .init(label: "type", insertText: "type", documentation: "Wrapper type label.", kind: .property, priority: 500),
        .init(label: "handleID", insertText: "handleID", documentation: "Stable handle identity for the current image.", kind: .property, priority: 500),
        .init(label: "width", insertText: "width", documentation: "Image width in pixels.", kind: .property, priority: 500),
        .init(label: "height", insertText: "height", documentation: "Image height in pixels.", kind: .property, priority: 500),
        .init(label: "isFlipped", insertText: "isFlipped", documentation: "Whether the image is vertically flipped.", kind: .property, priority: 500),
        .init(label: "pixelFormat", insertText: "pixelFormat", documentation: "Metal pixel format name.", kind: .property, priority: 500),
    ]

    private static let geometryEntries: [JavaScriptCompletionEntry] = [
        .init(label: "type", insertText: "type", documentation: "Wrapper type label.", kind: .property, priority: 500),
        .init(label: "handleID", insertText: "handleID", documentation: "Stable handle identity for the current geometry.", kind: .property, priority: 500),
        .init(label: "vertexCount", insertText: "vertexCount", documentation: "Geometry vertex count.", kind: .property, priority: 500),
        .init(label: "indexCount", insertText: "indexCount", documentation: "Geometry index count.", kind: .property, priority: 500),
        .init(label: "boundsMin", insertText: "boundsMin", documentation: "Minimum geometry bounds vector.", kind: .property, priority: 500),
        .init(label: "boundsMax", insertText: "boundsMax", documentation: "Maximum geometry bounds vector.", kind: .property, priority: 500),
    ]

    private static let materialEntries: [JavaScriptCompletionEntry] = [
        .init(label: "type", insertText: "type", documentation: "Wrapper type label.", kind: .property, priority: 500),
        .init(label: "handleID", insertText: "handleID", documentation: "Stable handle identity for the current material.", kind: .property, priority: 500),
        .init(label: "label", insertText: "label", documentation: "Material label.", kind: .property, priority: 500),
        .init(label: "hasShader", insertText: "hasShader", documentation: "Whether a shader is attached.", kind: .property, priority: 500),
        .init(label: "parameterCount", insertText: "parameterCount", documentation: "Number of exposed material parameters.", kind: .property, priority: 500),
        .init(label: "blending", insertText: "blending", documentation: "Material blending mode.", kind: .property, priority: 500),
    ]

    func openDocument(with text: String, locationService: LocationService) async throws
    {
        self.documentText = text
        self.locationService = locationService
        self.isOpen = true
        self.reparseSignature()
    }

    func documentDidChange(position changeLocation: Int,
                           changeInLength delta: Int,
                           lineChange deltaLine: Int,
                           columnChange deltaColumn: Int,
                           newText text: String) async throws
    {
        let nsText = self.documentText as NSString
        let replacedLength = max(0, text.utf16.count - delta)
        let replaceRange = NSRange(location: changeLocation, length: replacedLength)

        if NSMaxRange(replaceRange) <= nsText.length {
            self.documentText = nsText.replacingCharacters(in: replaceRange, with: text)
        }
        else {
            self.documentText = text
        }

        self.reparseSignature()
    }

    func closeDocument() async throws
    {
        self.documentText = ""
        self.signature = nil
        self.locationService = nil
        self.isOpen = false
    }

    func completions(at location: Int, reason: CompletionTriggerReason) async throws -> Completions
    {
        let clampedLocation = max(0, min(location, (self.documentText as NSString).length))

        if let propertyContext = self.propertyCompletionContext(at: clampedLocation) {
            return self.makeCompletions(entries: propertyContext.entries,
                                        prefix: propertyContext.prefix,
                                        insertRange: propertyContext.insertRange,
                                        selectedLabel: nil)
        }

        let identifierRange = self.identifierRange(at: clampedLocation)
        let prefix = self.substring(in: NSRange(location: identifierRange.location,
                                               length: clampedLocation - identifierRange.location))

        let isReturnObjectContext = self.isInsideReturnObject(at: clampedLocation)
        let outputEntries = self.outputCompletionEntries(prioritizedForReturnObject: isReturnObjectContext)
        let inputEntries = self.inputCompletionEntries()
        let entries = outputEntries + inputEntries + Self.builtinEntries + Self.keywordEntries

        let selectedLabel: String?
        if isReturnObjectContext {
            selectedLabel = self.firstMissingOutputLabel()
        }
        else {
            selectedLabel = nil
        }

        return self.makeCompletions(entries: entries,
                                    prefix: prefix,
                                    insertRange: identifierRange,
                                    selectedLabel: selectedLabel)
    }

    func tokens(for lineRange: Range<Int>) async throws -> [[(token: LanguageConfiguration.Token, range: NSRange)]]
    {
        Array(repeating: [], count: max(0, lineRange.count))
    }

    func info(at location: Int) async throws -> (view: any View, anchor: NSRange?)?
    {
        nil
    }

    func capabilities() async throws -> (any View)?
    {
        Text("Local JavaScript completions for Fabric JS nodes.")
    }

    private func reparseSignature()
    {
        self.signature = try? JavaScriptNodeSourceParser.parse(source: self.documentText)
    }

    private func inputCompletionEntries() -> [JavaScriptCompletionEntry]
    {
        (self.signature?.inputs ?? []).map { definition in
            JavaScriptCompletionEntry(label: definition.name,
                                      insertText: definition.name,
                                      documentation: "Input \(definition.name): \(definition.portType.rawValue)",
                                      kind: .input,
                                      priority: 400)
        }
    }

    private func outputCompletionEntries(prioritizedForReturnObject: Bool) -> [JavaScriptCompletionEntry]
    {
        (self.signature?.outputs ?? []).map { definition in
            JavaScriptCompletionEntry(label: definition.name,
                                      insertText: prioritizedForReturnObject ? "\(definition.name): " : definition.name,
                                      documentation: "Output \(definition.name): \(definition.portType.rawValue)",
                                      kind: .output,
                                      priority: prioritizedForReturnObject ? 600 : 200)
        }
    }

    private func firstMissingOutputLabel() -> String?
    {
        guard let signature else { return nil }
        let usedKeys = self.usedOutputKeys()

        for output in signature.outputs where usedKeys.contains(output.name) == false {
            return output.name
        }

        return signature.outputs.first?.name
    }

    private func usedOutputKeys() -> Set<String>
    {
        guard let signature else { return [] }
        guard let returnRange = self.currentReturnObjectRange() else { return [] }

        let returnText = self.substring(in: returnRange)
        var result = Set<String>()
        for output in signature.outputs {
            let pattern = #"(?m)\b"# + NSRegularExpression.escapedPattern(for: output.name) + #"\s*:"# 
            if returnText.range(of: pattern, options: .regularExpression) != nil {
                result.insert(output.name)
            }
        }
        return result
    }

    private func makeCompletions(entries: [JavaScriptCompletionEntry],
                                 prefix: String,
                                 insertRange: NSRange,
                                 selectedLabel: String?) -> Completions
    {
        let filteredEntries = entries
            .filter { prefix.isEmpty || $0.label.hasPrefix(prefix) }
            .sorted {
                if $0.priority == $1.priority {
                    return $0.label < $1.label
                }
                return $0.priority > $1.priority
            }

        var items: [Completions.Completion] = []
        items.reserveCapacity(filteredEntries.count)

        for (index, entry) in filteredEntries.enumerated() {
            let isSelected = if let selectedLabel { entry.label == selectedLabel } else { index == 0 }

            items.append(
                Completions.Completion(
                    id: index,
                    rowView: { selected in
                        Text("\(entry.label)  \(entry.kind.rawValue)")
                            .font(.caption.monospaced())
                            .foregroundStyle(selected ? .primary : .secondary)
                    },
                    documentationView: Text(entry.documentation)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading),
                    selected: isSelected,
                    sortText: "\(999 - entry.priority)-\(entry.label)",
                    filterText: entry.label,
                    insertText: entry.insertText,
                    insertRange: insertRange,
                    commitCharacters: [".", ",", ":", "(", " "],
                    refine: { nil }
                )
            )
        }

        return Completions(isIncomplete: false, items: items)
    }

    private func propertyCompletionContext(at location: Int) -> (entries: [JavaScriptCompletionEntry], prefix: String, insertRange: NSRange)?
    {
        let nsText = self.documentText as NSString
        let propertyRange = self.identifierRange(at: location)
        let prefix = self.substring(in: NSRange(location: propertyRange.location,
                                               length: location - propertyRange.location))

        var cursor = propertyRange.location - 1
        while cursor >= 0, self.character(at: cursor).isWhitespace {
            cursor -= 1
        }

        guard cursor >= 0, self.character(at: cursor) == "." else { return nil }

        cursor -= 1
        while cursor >= 0, self.character(at: cursor).isWhitespace {
            cursor -= 1
        }

        guard cursor >= 0 else { return nil }
        let ownerRange = self.identifierRangeEnding(at: cursor + 1)
        let ownerName = nsText.substring(with: ownerRange)

        if let builtInEntries = Self.propertyEntries(for: ownerName) {
            return (builtInEntries, prefix, propertyRange)
        }

        if let inputType = self.signature?.inputs.first(where: { $0.name == ownerName })?.portType {
            switch inputType
            {
            case .Image:
                return (Self.imageEntries, prefix, propertyRange)
            case .Geometry:
                return (Self.geometryEntries, prefix, propertyRange)
            case .Material:
                return (Self.materialEntries, prefix, propertyRange)
            default:
                return nil
            }
        }

        return nil
    }

    private static func propertyEntries(for ownerName: String) -> [JavaScriptCompletionEntry]?
    {
        switch ownerName
        {
        case "context":
            Self.contextEntries
        case "console":
            Self.consoleEntries
        case "Math":
            Self.mathEntries
        case "Object":
            Self.objectEntries
        case "Array":
            Self.arrayEntries
        case "JSON":
            Self.jsonEntries
        case "Number":
            Self.numberEntries
        case "String":
            Self.stringEntries
        case "Date":
            Self.dateEntries
        default:
            nil
        }
    }

    private func isInsideReturnObject(at location: Int) -> Bool
    {
        guard let range = self.currentReturnObjectRange() else { return false }
        return NSLocationInRange(location, range)
    }

    private func currentReturnObjectRange() -> NSRange?
    {
        let nsText = self.documentText as NSString
        let pattern = #"return\s*\{"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: self.documentText, range: NSRange(location: 0, length: nsText.length))

        for match in matches.reversed() {
            let bodyStart = match.range.location + match.range.length
            var depth = 1
            var index = bodyStart

            while index < nsText.length {
                let character = nsText.substring(with: NSRange(location: index, length: 1))
                if character == "{" {
                    depth += 1
                }
                else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return NSRange(location: bodyStart, length: index - bodyStart)
                    }
                }
                index += 1
            }

            return NSRange(location: bodyStart, length: nsText.length - bodyStart)
        }

        return nil
    }

    private func identifierRange(at location: Int) -> NSRange
    {
        let nsText = self.documentText as NSString
        var start = location
        var end = location

        while start > 0, self.isIdentifierCharacter(nsText.character(at: start - 1)) {
            start -= 1
        }

        while end < nsText.length, self.isIdentifierCharacter(nsText.character(at: end)) {
            end += 1
        }

        return NSRange(location: start, length: end - start)
    }

    private func identifierRangeEnding(at location: Int) -> NSRange
    {
        let nsText = self.documentText as NSString
        var start = max(0, location)
        var end = max(0, location)

        while start > 0, self.isIdentifierCharacter(nsText.character(at: start - 1)) {
            start -= 1
        }

        while end < nsText.length, self.isIdentifierCharacter(nsText.character(at: end)) {
            end += 1
        }

        return NSRange(location: start, length: end - start)
    }

    private func isIdentifierCharacter(_ value: unichar) -> Bool
    {
        guard let scalar = UnicodeScalar(value) else { return false }
        return Self.identifierCharacters.contains(scalar)
    }

    private func substring(in range: NSRange) -> String
    {
        let nsText = self.documentText as NSString
        guard range.location >= 0, NSMaxRange(range) <= nsText.length else { return "" }
        return nsText.substring(with: range)
    }

    private func character(at index: Int) -> Character
    {
        Character(self.substring(in: NSRange(location: index, length: 1)))
    }
}
