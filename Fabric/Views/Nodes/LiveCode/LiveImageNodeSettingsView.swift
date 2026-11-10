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
    typealias ShaderDiagnostic = MetalCompileDiagnostic

    var content: String
    private weak var node: LiveImageNode?
    private var saveTimer: Timer?
    /// What the node held at the last flush: the editor writes only what was edited since.
    private var savedContent: String
    var messages: Set<TextLocated<Message>> = Set()
    var diagnostics: [ShaderDiagnostic] = []

    init(node: LiveImageNode) {
        self.node = node
        self.content = node.shaderSource
        self.savedContent = node.shaderSource
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

    /// Writes what was edited since the last flush and nothing else, so an
    /// editor closed unedited keeps settings applied to the node meanwhile.
    func flush() {
        guard let node else { return }
        if self.content != self.savedContent {
            node.setSettings(LiveImageSettings(shaderSource: self.content))
            self.savedContent = node.shaderSource
        }
        self.refreshErrorMessagesIfPossible()
    }

    /// Takes the node's source where it changed under the editor, as a value
    /// applied to the node or the file on disk read on save; an edit not yet
    /// flushed goes.
    func refreshFromNode() {
        guard let node else { return }
        if node.shaderSource != self.savedContent {
            self.savedContent = node.shaderSource
            self.content = node.shaderSource
        }
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

        self.diagnostics = MetalCompileDiagnostics.diagnostics(fromLog: errorDescription, editedSource: self.content)
        self.messages = MetalCompileDiagnostics.messages(for: self.diagnostics)
    }
}

struct LiveImageNodeSettingsView: View
{
    @Bindable var editorModel: LiveImageNodeEditorModel
    @State private var position: CodeEditor.Position = .init()

    init(editorModel: LiveImageNodeEditorModel) {
        self.editorModel = editorModel
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            CodeEditorGuidance(
                "Process an image using a Metal fragment shader. `postFragment` is the entry point, sampling `inputTexture` through `imageTransforms[0]`, and each field of `PostUniforms` becomes an input port — the trailing comment giving its control, range, default and name, as `float amount; // slider, 0.0, 1.0, 1.0, Amount`.",
                guide: "[Metal Shading Language specification ↗](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)")

            CodeEditor(text: self.$editorModel.content,
                       position: self.$position,
                       messages: self.$editorModel.messages,
                       language: .metalShaderLanguage())
            .codeEditorChrome()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: self.editorModel.content) { _, _ in
                self.editorModel.scheduleSave()
            }
            .onDisappear {
                self.editorModel.flush()
            }
        }
        .padding(10)
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

