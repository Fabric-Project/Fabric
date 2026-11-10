//
//  MetalKernelEditor.swift
//  Fabric
//

import SwiftUI
import CodeEditorView
import LanguageSupport

/// A node whose settings hold a Metal function the user edits, which the node wraps in a kernel.
protocol MetalKernelSourceEditing: AnyObject
{
    /// The function as the user wrote it.
    var editableKernelSource: String { get }
    /// Takes `source` into the node's settings, keeping the rest of them, which recompiles it.
    func applyEditedKernelSource(_ source: String)
    /// What the last compile reported, or nil when it compiled.
    var kernelCompileFailure: String? { get }
}

/// The code editor's model for a Metal kernel node: edits save a moment after typing stops, as Live
/// Image's do, and compile errors show on the lines they name.
@MainActor
@Observable final class MetalKernelEditorModel
{
    var content: String
    var messages: Set<TextLocated<Message>> = Set()
    private weak var node: (any MetalKernelSourceEditing)?
    private var saveTimer: Timer?
    /// What the node held at the last flush: the editor writes only what was edited since.
    private var savedContent: String

    init(node: any MetalKernelSourceEditing)
    {
        self.node = node
        self.content = node.editableKernelSource
        self.savedContent = node.editableKernelSource
        refreshMessages()
    }

    func scheduleSave()
    {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.flush() }
        }
    }

    /// Writes what was edited since the last flush and nothing else, so an editor closed unedited
    /// keeps settings applied to the node meanwhile.
    func flush()
    {
        guard let node else { return }
        if content != savedContent
        {
            node.applyEditedKernelSource(content)
            savedContent = node.editableKernelSource
        }
        refreshMessages()
    }

    /// Takes the node's source where it changed under the editor, such as by undo; an edit not yet
    /// flushed goes.
    func refreshFromNode()
    {
        guard let node else { return }
        if node.editableKernelSource != savedContent
        {
            savedContent = node.editableKernelSource
            content = node.editableKernelSource
        }
        refreshMessages()
    }

    private func refreshMessages()
    {
        guard let failure = node?.kernelCompileFailure, failure.isEmpty == false else
        {
            messages.removeAll()
            return
        }
        messages = MetalCompileDiagnostics.messages(for: MetalCompileDiagnostics.diagnostics(fromLog: failure, editedSource: content))
    }
}

/// The shared code editor for a Metal kernel's function, filling the room it is given.
struct MetalKernelCodeEditor: View
{
    @Bindable var model: MetalKernelEditorModel
    @State private var position: CodeEditor.Position = .init()

    var body: some View
    {
        CodeEditor(text: $model.content,
                   position: $position,
                   messages: $model.messages,
                   language: .metalShaderLanguage())
        .codeEditorChrome()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.content) { _, _ in
            model.scheduleSave()
        }
        .onDisappear {
            model.flush()
        }
    }
}

/// What a kernel's function sees, collapsed until asked for.
struct MetalKernelDeclarations: View
{
    let declarations: String

    var body: some View
    {
        DisclosureGroup("Declarations")
        {
            ScrollView
            {
                Text(declarations)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
        }
    }
}
