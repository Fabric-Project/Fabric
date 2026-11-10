//
//  MetalCompileDiagnostics.swift
//  Fabric
//

import Foundation
import LanguageSupport

/// One problem a Metal compile reported, placed on a line of the source the user edits.
struct MetalCompileDiagnostic: Hashable
{
    let line: Int
    let column: Int
    let category: Message.Category
    let summary: String
    let context: String
    /// What the editor shows on hover: the offending line, or the whole log when it couldn't be read.
    let detail: String
}

/// Reads a Metal compiler log into diagnostics on the source a user edits, which may be only part of
/// what was compiled: a reported line is matched back by the text the compiler quoted from it.
enum MetalCompileDiagnostics
{
    /// The log's errors, warnings and notes; one error naming the log's first line when none can be read.
    static func diagnostics(fromLog log: String, editedSource: String) -> [MetalCompileDiagnostic]
    {
        // Compiler logs typically look like:
        // program_source:12:9: error: use of undeclared identifier 'foo'
        let primaryPattern = #"program_source:(\d+):(\d+):\s*(error|warning|note):\s*([^\n]+)(?:\n([^\n]*))?"#
        let fallbackPattern = #"[^:\n]+:(\d+):(\d+):\s*(error|warning|note):\s*([^\n]+)(?:\n([^\n]*))?"#

        var parsed = diagnostics(fromLog: log, editedSource: editedSource, regexPattern: primaryPattern)
        if parsed.isEmpty
        {
            parsed = diagnostics(fromLog: log, editedSource: editedSource, regexPattern: fallbackPattern)
        }
        if parsed.isEmpty
        {
            let summary = log.components(separatedBy: .newlines).first(where: { $0.isEmpty == false }) ?? "Shader compilation failed."
            parsed = [MetalCompileDiagnostic(line: 0, column: 0, category: .error, summary: summary, context: "", detail: log)]
        }
        return parsed
    }

    /// The editor's messages for `diagnostics`.
    static func messages(for diagnostics: [MetalCompileDiagnostic]) -> Set<TextLocated<Message>>
    {
        Set(diagnostics.map { diagnostic in
            let message = Message(category: diagnostic.category,
                                  length: max(1, diagnostic.context.count),
                                  summary: diagnostic.summary,
                                  description: AttributedString(diagnostic.detail))
            return TextLocated(location: TextLocation(zeroBasedLine: max(0, diagnostic.line), column: max(0, diagnostic.column)),
                               entity: message)
        })
    }

    private static func diagnostics(fromLog log: String, editedSource: String, regexPattern: String) -> [MetalCompileDiagnostic]
    {
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else { return [] }

        var diagnostics: [MetalCompileDiagnostic] = []
        for match in regex.matches(in: log, range: NSRange(log.startIndex..., in: log))
        {
            guard let lineRange = Range(match.range(at: 1), in: log),
                  let columnRange = Range(match.range(at: 2), in: log),
                  let typeRange = Range(match.range(at: 3), in: log),
                  let summaryRange = Range(match.range(at: 4), in: log)
            else { continue }

            let context: String
            if match.range(at: 5).location != NSNotFound, let contextRange = Range(match.range(at: 5), in: log)
            {
                context = String(log[contextRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            else
            {
                context = ""
            }

            let rawLine = Int(log[lineRange]) ?? 1
            let rawColumn = Int(log[columnRange]) ?? 1
            diagnostics.append(MetalCompileDiagnostic(line: editedLine(quoting: context, in: editedSource) ?? max(0, rawLine - 1),
                                                      column: max(0, rawColumn - 1),
                                                      category: category(for: String(log[typeRange])),
                                                      summary: String(log[summaryRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                                                      context: context,
                                                      detail: context))
        }
        return diagnostics
    }

    /// The edited line holding the text the compiler quoted, since the compiled source may hold more
    /// than the user wrote.
    private static func editedLine(quoting quoted: String, in editedSource: String) -> Int?
    {
        guard quoted.isEmpty == false else { return nil }
        return editedSource.components(separatedBy: .newlines).firstIndex { $0.localizedStandardContains(quoted) }
    }

    private static func category(for label: String) -> Message.Category
    {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        {
        case "warning": return .warning
        case "note": return .informational
        default: return .error
        }
    }
}
