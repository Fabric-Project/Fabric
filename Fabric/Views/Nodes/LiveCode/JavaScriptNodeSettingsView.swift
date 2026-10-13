//
//  JavaScriptNodeSettingsView.swift
//  Fabric
//
//  Created by Codex on 3/13/26.
//

import SwiftUI
import Combine
import CodeEditorView
import LanguageSupport

/// The script editor's draft, committed after a pause in typing and when the
/// editor goes; a time mode is committed as it is picked.
@MainActor
@Observable final class JavaScriptNodeEditorModel
{
    let draft: NodeSettingsDraft<JavaScriptSettings>

    var content: String
    {
        get { draft.value.scriptSource }
        set { draft.value.scriptSource = newValue }
    }

    var selectedTimeMode: Node.TimeMode
    {
        get { draft.value.selectedTimeMode }
        set
        {
            draft.value.selectedTimeMode = newValue
            draft.commit()
        }
    }

    var messages: Set<TextLocated<Message>> = []
    let languageService: JavaScriptLanguageService

    @ObservationIgnored private weak var node: JavaScriptNode?
    @ObservationIgnored private var subscription: AnyCancellable?

    init(node: JavaScriptNode)
    {
        self.node = node
        self.draft = NodeSettingsDraft(of: JavaScriptSettings(scriptSource: node.scriptSource, selectedTimeMode: node.selectedTimeMode),
                                       on: node,
                                       commit: .afterPause,
                                       pause: .milliseconds(200))
        self.languageService = JavaScriptLanguageService()
        self.refreshMessages()
        // A commit compiles the script; what the compile had to say follows.
        self.subscription = node.settingsChangedSubject.sink { [weak self] in
            MainActor.assumeIsolated { self?.refreshMessages() }
        }
    }

    var diagnostics: [JavaScriptNodeDiagnostic]
    {
        node?.currentDiagnostics ?? []
    }

    /// Read off the node, which reads it off the ports the script declares.
    var executionMode: Node.ExecutionMode
    {
        node?.nodeExecutionMode ?? .Processor
    }

    /// Commits the draft now.
    func flush()
    {
        draft.commit()
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
            CodeEditorGuidance(
                "Process Fabric data using a JavaScript function. The node's ports are set from the typed signature, and the function must return an object keyed by those output names. Types: `Bool`, `Int`, `Number`, `String`, `Vector2`/`3`/`4`, `Color`, `Quaternion`, `Transform`, `Geometry`, `Material`, `Image`, with `Type[]` for an array and `Record<string, Type>` for a dictionary. `context` is in scope, carrying `time`, `deltaTime`, `displayTime`, `systemTime`, `frameNumber`, `iterationIndex` and `iterationCount`.",
                guide: "[JavaScript node guide ↗](https://github.com/Fabric-Project/Fabric/blob/main/Fabric/Nodes/Utility/JavaScriptNodeGuidance.markdown)")

            HStack
            {
                LabeledContent("Execution") {
                    Text(self.editorModel.executionMode.rawValue)
                        .foregroundStyle(.secondary)
                }

                Picker("Time", selection: self.$editorModel.selectedTimeMode) {
                    Text("None").tag(Node.TimeMode.None)
                    Text("Idle").tag(Node.TimeMode.Idle)
                    Text("Time Base").tag(Node.TimeMode.TimeBase)
                }
                .pickerStyle(.segmented)
            }

            CodeEditor(text: self.$editorModel.content,
                       position: self.$position,
                       messages: self.$editorModel.messages,
                       language: .javaScriptLanguage(self.editorModel.languageService))
            .codeEditorChrome()
            .withoutTypingUndo()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
