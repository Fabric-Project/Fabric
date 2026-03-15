//
//  LiveImageNodeSettingsView.swift
//  Fabric
//
//  Created by Codex on 3/4/26.
//

import SwiftUI
import CodeEditorView
import LanguageSupport

@MainActor
@Observable final class LiveImageNodeEditorModel
{
    struct ShaderDiagnostic: Hashable {
        let line: Int
        let column: Int
        let category: Message.Category
        let summary: String
        let context: String
    }

    var content: String
    private weak var node: LiveImageNode?
    private var saveTimer: Timer?
    var messages: Set<TextLocated<Message>> = Set()
    var diagnostics: [ShaderDiagnostic] = []

    init(node: LiveImageNode) {
        self.node = node
        self.content = node.shaderSource
    }

    func scheduleSave() {
        self.saveTimer?.invalidate()
        self.saveTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.flush()
            }
        }
    }

    func flush() {
        guard let node else { return }
        node.updateShaderSource(self.content)
        self.refreshErrorMessagesIfPossible()
    }

    private func refreshErrorMessagesIfPossible() {
        self.messages.removeAll()
        self.diagnostics.removeAll()

        guard let node,
              let errorDescription = node.currentShaderErrorDescription(),
              errorDescription.isEmpty == false else {
            return
        }

        self.parseErrorString(errorDescription)
    }

    private func parseErrorString(_ errorText: String) {
        let parsedDiagnostics = self.parseShaderLog(errorText)
        if parsedDiagnostics.isEmpty {
            let fallbackSummary = errorText.components(separatedBy: .newlines).first(where: { $0.isEmpty == false }) ?? "Shader compilation failed."
            let message = Message(category: .error,
                                  length: max(1, fallbackSummary.count),
                                  summary: fallbackSummary,
                                  description: AttributedString(errorText))
            let location = TextLocation(zeroBasedLine: 0, column: 0)
            self.messages.insert(TextLocated(location: location, entity: message))
            self.diagnostics = [.init(line: 0, column: 0, category: .error, summary: fallbackSummary, context: "")]
            return
        }

        self.diagnostics = parsedDiagnostics
        for diagnostic in parsedDiagnostics {
            let message = Message(category: diagnostic.category,
                                  length: max(1, diagnostic.context.count),
                                  summary: diagnostic.summary,
                                  description: AttributedString(diagnostic.context))
            let location = TextLocation(zeroBasedLine: max(0, diagnostic.line), column: max(0, diagnostic.column))
            self.messages.insert(TextLocated(location: location, entity: message))
        }
    }

    private func parseShaderLog(_ log: String) -> [ShaderDiagnostic] {
        // SourceShader logs typically look like:
        // program_source:12:9: error: use of undeclared identifier 'foo'
        let primaryPattern = #"program_source:(\d+):(\d+):\s*(error|warning|note):\s*([^\n]+)(?:\n([^\n]*))?"#
        let fallbackPattern = #"[^:\n]+:(\d+):(\d+):\s*(error|warning|note):\s*([^\n]+)(?:\n([^\n]*))?"#

        var parsed = self.parseShaderLog(log, regexPattern: primaryPattern)
        if parsed.isEmpty {
            parsed = self.parseShaderLog(log, regexPattern: fallbackPattern)
        }
        return parsed
    }

    private func parseShaderLog(_ log: String, regexPattern: String) -> [ShaderDiagnostic] {
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return []
        }

        let matches = regex.matches(in: log, range: NSRange(log.startIndex..., in: log))
        var diagnostics: [ShaderDiagnostic] = []

        for match in matches {
            guard let lineRange = Range(match.range(at: 1), in: log),
                  let columnRange = Range(match.range(at: 2), in: log),
                  let typeRange = Range(match.range(at: 3), in: log),
                  let summaryRange = Range(match.range(at: 4), in: log) else {
                continue
            }

            let context: String
            if match.range(at: 5).location != NSNotFound,
               let contextRange = Range(match.range(at: 5), in: log) {
                context = String(log[contextRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            else {
                context = ""
            }

            let rawLine = Int(log[lineRange]) ?? 1
            let rawColumn = Int(log[columnRange]) ?? 1
            let category = self.messageCategory(for: String(log[typeRange]))
            let summary = String(log[summaryRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            let remappedLine = self.remapCompiledErrorLine(sourceSubstring: context) ?? max(0, rawLine - 1)
            let diagnostic = ShaderDiagnostic(line: remappedLine,
                                              column: max(0, rawColumn - 1),
                                              category: category,
                                              summary: summary,
                                              context: context)
            diagnostics.append(diagnostic)
        }

        return diagnostics
    }

    private func remapCompiledErrorLine(sourceSubstring: String) -> Int? {
        guard sourceSubstring.isEmpty == false else { return nil }
        let sourceLines = self.content.components(separatedBy: .newlines)

        for (lineIndex, sourceLine) in sourceLines.enumerated() {
            if sourceLine.localizedStandardContains(sourceSubstring) {
                return lineIndex
            }
        }
        return nil
    }

    private func messageCategory(for label: String) -> Message.Category {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "warning":
            return .warning
        case "note":
            return .informational
        default:
            return .error
        }
    }
}

struct LiveImageNodeSettingsView: View
{
    @State private var editorModel: LiveImageNodeEditorModel
    @State private var position: CodeEditor.Position = .init()

    init(node: LiveImageNode) {
        _editorModel = State(initialValue: LiveImageNodeEditorModel(node: node))
    }

    var body: some View {

        CodeEditor(text: self.$editorModel.content,
                   position: self.$position,
                   messages: self.$editorModel.messages,
                   language: .metalShaderLanguage(),
                   layout: CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: true))
        

        .environment(\.codeEditorTheme, Theme.vDark )
        .onChange(of: self.editorModel.content) { _, _ in
            self.editorModel.scheduleSave()
        }
        .onDisappear {
            self.editorModel.flush()
        }
    }

    private func diagnosticLineText(_ diagnostic: LiveImageNodeEditorModel.ShaderDiagnostic) -> String {
        let category: String
        switch diagnostic.category {
        case .warning:
            category = "warning"
        case .informational:
            category = "note"
        default:
            category = "error"
        }

        let lineColumn = "L\(diagnostic.line + 1):C\(diagnostic.column + 1)"
        if diagnostic.context.isEmpty {
            return "\(lineColumn) \(category): \(diagnostic.summary)"
        }
        return "\(lineColumn) \(category): \(diagnostic.summary)\n\(diagnostic.context)"
    }

    private func diagnosticColor(_ category: Message.Category) -> Color {
        switch category {
        case .warning:
            return .yellow
        case .informational:
            return .blue
        default:
            return .red
        }
    }
}


extension Theme {
    
    public static var vDark: Theme {
        var theme = Theme.defaultDark
        theme.fontName = "SFMono-Medium"
        theme.fontSize = 11.0
        return theme
    }
}
