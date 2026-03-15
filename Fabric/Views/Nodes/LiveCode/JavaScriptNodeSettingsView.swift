//
//  JavaScriptNodeSettingsView.swift
//  Fabric
//
//  Created by Codex on 3/13/26.
//

import SwiftUI
import CodeEditorView
import LanguageSupport

@MainActor
@Observable final class JavaScriptNodeEditorModel
{
    var content: String
    var selectedExecutionMode: Node.ExecutionMode
    var selectedTimeMode: Node.TimeMode
    var messages: Set<TextLocated<Message>> = []
    let languageService: JavaScriptLanguageService

    private weak var node: JavaScriptNode?
    private var saveTimer: Timer?

    init(node: JavaScriptNode)
    {
        self.node = node
        self.content = node.scriptSource
        self.selectedExecutionMode = node.selectedExecutionMode
        self.selectedTimeMode = node.selectedTimeMode
        self.languageService = JavaScriptLanguageService()
        self.refreshMessages()
    }

    var portPreview: [JavaScriptNodePortDefinition]
    {
        node?.portPreview ?? []
    }

    var diagnostics: [JavaScriptNodeDiagnostic]
    {
        node?.currentDiagnostics ?? []
    }

    func scheduleSave()
    {
        self.saveTimer?.invalidate()
        self.saveTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flush()
            }
        }
    }

    func flush()
    {
        guard let node else { return }
        node.updateScriptSource(self.content)
        node.updateModes(executionMode: self.selectedExecutionMode, timeMode: self.selectedTimeMode)
        self.refreshMessages()
    }

    func refreshMessages()
    {
        self.messages = Set(self.diagnostics.map { diagnostic in
            let category: Message.Category = diagnostic.severity == .warning ? .warning : .error
            let message = Message(category: category,
                                  length: max(1, diagnostic.summary.count),
                                  summary: diagnostic.summary,
                                  description: AttributedString(diagnostic.detail.isEmpty ? diagnostic.summary : diagnostic.detail))
            let location = TextLocation(zeroBasedLine: max(0, diagnostic.line), column: max(0, diagnostic.column))
            return TextLocated(location: location, entity: message)
        })
    }
}

struct JavaScriptNodeSettingsView: View
{
    @State private var editorModel: JavaScriptNodeEditorModel
    @State private var position: CodeEditor.Position = .init()

    init(node: JavaScriptNode)
    {
        _editorModel = State(initialValue: JavaScriptNodeEditorModel(node: node))
    }

    var body: some View
    {
        VStack(alignment: .leading, spacing: 12)
        {
            HStack
            {
                Picker("Execution", selection: self.$editorModel.selectedExecutionMode) {
                    Text("Provider").tag(Node.ExecutionMode.Provider)
                    Text("Processor").tag(Node.ExecutionMode.Processor)
                    Text("Consumer").tag(Node.ExecutionMode.Consumer)
                }

                Picker("Time", selection: self.$editorModel.selectedTimeMode) {
                    Text("None").tag(Node.TimeMode.None)
                    Text("Idle").tag(Node.TimeMode.Idle)
                    Text("Time Base").tag(Node.TimeMode.TimeBase)
                }
            }
            .pickerStyle(.segmented)

            CodeEditor(text: self.$editorModel.content,
                       position: self.$position,
                       messages: self.$editorModel.messages,
                       language: .javaScriptLanguage(self.editorModel.languageService))
            .environment(\.codeEditorTheme, Theme.vDark)
            .environment(\.codeEditorLayoutConfiguration, .init(showMinimap: false, wrapText: true))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: self.editorModel.content) { _, _ in
                self.editorModel.scheduleSave()
            }
            .onChange(of: self.editorModel.selectedExecutionMode) { _, _ in
                self.editorModel.scheduleSave()
            }
            .onChange(of: self.editorModel.selectedTimeMode) { _, _ in
                self.editorModel.scheduleSave()
            }

            GroupBox("Ports")
            {
                ScrollView
                {
                    VStack(alignment: .leading, spacing: 6)
                    {
                        ForEach(Array(self.editorModel.portPreview.enumerated()), id: \.offset) { _, port in
                            Text("\(port.direction == .input ? "In" : "Out")  \(port.name): \(port.portType.rawValue)")
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
            }

            if self.editorModel.diagnostics.isEmpty == false {
                GroupBox("Diagnostics")
                {
                    ScrollView
                    {
                        VStack(alignment: .leading, spacing: 8)
                        {
                            ForEach(Array(self.editorModel.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                                let lineColumn = "L\(diagnostic.line + 1):C\(diagnostic.column + 1)"
                                Text("\(lineColumn) \(diagnostic.summary)")
                                    .font(.caption.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 110)
                }
            }
        }
        .onDisappear {
            self.editorModel.flush()
        }
    }
}
