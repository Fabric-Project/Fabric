//
//  MathExpressionNode.swift
//  Fabric
//
//  The Math Expression node, backed by the standalone MathExpressionEngine.
//  The expression is the single source of truth: free identifiers become typed
//  input ports, `out name = …` declarations become typed output ports, and the
//  whole port interface is derived from — and kept in sync with — the compiled
//  expression. Unlike the previous scalar-only (swift-math-parser) version this
//  supports vectors, transforms, quaternions and arrays, and multiple outputs.
//

import Foundation
import Satin
import Metal
import SwiftUI
import simd
import MathExpressionEngine
import CodeEditorView
import LanguageSupport

// MARK: - Settings View

struct MathExpressionView: View
{
    @Bindable var model: MathExpressionNode.SettingsModel

    // Editor disclosure lives on the (observable) model so the node's
    // `settingsSize` reacts to it too. The single-line field is the resting
    // state; the code editor appears when the expression spans multiple
    // statements (a `;` or newline) or when explicitly expanded — so a one-liner
    // always opens simple and compact, and the mode needs no persistence.
    @State private var editorPosition = CodeEditor.Position()
    @State private var editorMessages: Set<TextLocated<Message>> = []

    private var isMultiStatement: Bool
    {
        model.stringExpression.contains(";") || model.stringExpression.contains("\n")
    }

    var body: some View
    {
        VStack(alignment: .leading, spacing: 8)
        {
            Text("Write an expression — free names become input ports, results become output ports. Beyond numbers, values can be vectors, transforms or arrays, and a single expression can drive several named inputs and outputs at once.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("[Language guide ↗](https://github.com/tobyspark/MathExpressionEngine/blob/main/GUIDE.md)")
                .font(.caption)

            if model.showsCode { codeEditor } else { simpleField }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .onAppear { rebuildMessages() }
        .onChange(of: model.diagnostics) { rebuildMessages() }
        .onChange(of: model.stringExpression) { rebuildMessages() }
    }

    // Simple: single-line field, an "edit as code" affordance, and the compact
    // diagnostics list (the field can't place errors inline).
    @ViewBuilder
    private var simpleField: some View
    {
        HStack(spacing: 6)
        {
            TextField("Expression", text: $model.stringExpression)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            Button { model.expandedToCode = true } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(.borderless)
            .help("Edit as code")
        }

        diagnostics
    }

    // Code: multi-line editor with diagnostics rendered inline at their span.
    // Collapse is offered only while the expression is still a single line — a
    // multi-statement one can't fold back into the single-line field.
    @ViewBuilder
    private var codeEditor: some View
    {
        CodeEditor(text: $model.stringExpression,
                   position: $editorPosition,
                   messages: $editorMessages,
                   layout: CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: true))
            .frame(maxWidth: .infinity, minHeight: 300)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))

        if !isMultiStatement
        {
            Button { model.expandedToCode = false } label: {
                Label("Collapse", systemImage: "chevron.up").font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var diagnostics: some View
    {
        if model.diagnostics.isEmpty
        {
            Label("Valid", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        }
        else
        {
            VStack(alignment: .leading, spacing: 3)
            {
                ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    HStack(alignment: .top, spacing: 5)
                    {
                        Image(systemName: diagnostic.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(diagnostic.severity == .error ? Color.red : Color.yellow)
                        Text(diagnostic.message)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    /// Rebuild the code editor's inline messages from the current diagnostics.
    private func rebuildMessages()
    {
        let source = model.stringExpression
        editorMessages = Set(model.diagnostics.map { located($0, in: source) })
    }

    /// Map an engine diagnostic (a character span) to a CodeEditor inline
    /// message at the corresponding line/column.
    private func located(_ diagnostic: Diagnostic, in source: String) -> TextLocated<Message>
    {
        let chars = Array(source)
        let start = max(0, min(diagnostic.span.start, chars.count))
        var line = 0
        var lineStart = 0
        var i = 0
        while i < start
        {
            if chars[i] == "\n" { line += 1; lineStart = i + 1 }
            i += 1
        }
        let column = start - lineStart

        let category: Message.Category
        switch diagnostic.severity
        {
        case .error:   category = .error
        case .warning: category = .warning
        default:       category = .informational
        }

        let message = Message(category: category,
                              length: max(1, diagnostic.span.length),
                              summary: diagnostic.message,
                              description: nil)
        return TextLocated(location: TextLocation(zeroBasedLine: line, column: column), entity: message)
    }
}

// MARK: - Node

public class MathExpressionNode: Node
{
    override public static var name: String { "Math Expression" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Write a math expression; its free variables become typed input ports and its results become typed output ports. Supports numbers, vectors, transforms, quaternions and arrays." }

    /// The default for a freshly created node (and the fallback when a document
    /// stored none). Two float inputs, one float output — identical to the
    /// previous node so existing behaviour is preserved.
    public class var defaultExpression: String { "sin(x) + y^2" }

    /// Shown as the node's title: the expression, or a ⚠-prefixed form on error.
    /// nil (empty) falls back to the type name; a user `userName` overrides this.
    override public var displayName: String? { evaluatedDisplayName.isEmpty ? nil : evaluatedDisplayName }
    private var evaluatedDisplayName: String = ""

    // MARK: - State

    var stringExpression: String
    {
        didSet
        {
            guard oldValue != stringExpression else { return }
            self.compileAndSync()
        }
    }

    /// The last compile. Recomputed only when `stringExpression` changes.
    private var compiled: CompileResult?

    /// The interface the current ports were built from — the last *valid*
    /// compile. A transiently invalid edit (e.g. `sin(`) keeps the existing
    /// ports and wires rather than churning them.
    private var portInterface: Interface = Interface(inputs: [], outputs: [])

    /// Force one evaluation after a (re)compile even if no input changed — a new
    /// program can produce a different result from unchanged inputs.
    private var needsEvaluation: Bool = true

    // MARK: - Init

    private enum CodingKeys: String, CodingKey { case stringExpression }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // didSet does not fire during init; compile explicitly after super.init.
        self.stringExpression = try container.decodeIfPresent(String.self, forKey: .stringExpression) ?? Self.defaultExpression
        try super.init(from: decoder)
        self.compileAndSync()
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.stringExpression, forKey: .stringExpression)
    }

    public required init(context: Context)
    {
        self.stringExpression = Self.defaultExpression
        super.init(context: context)
        self.compileAndSync()
    }

    public convenience init(context: Context, expression: String)
    {
        self.init(context: context)
        // didSet does not fire for assignments inside an initializer.
        self.stringExpression = expression
        self.compileAndSync()
    }

    // MARK: - Settings

    @Observable final class SettingsModel
    {
        var stringExpression: String
        {
            didSet
            {
                guard stringExpression != node?.stringExpression else { return }
                node?.stringExpression = stringExpression
            }
        }

        /// Compiler diagnostics for the current expression, surfaced in the UI.
        var diagnostics: [Diagnostic] = []

        /// Whether the user explicitly expanded the code editor. Observable so
        /// both the settings view and the node's `settingsSize` react to it.
        var expandedToCode = false

        /// Show the code editor when explicitly expanded, or when the expression
        /// spans multiple statements (a `;` or newline). A one-liner opens simple.
        var showsCode: Bool
        {
            expandedToCode || stringExpression.contains(";") || stringExpression.contains("\n")
        }

        private weak var node: MathExpressionNode?

        init(node: MathExpressionNode)
        {
            self.node = node
            self.stringExpression = node.stringExpression
            self.diagnostics = node.compiled?.diagnostics ?? []
        }
    }

    internal lazy var _settingsModel: SettingsModel = SettingsModel(node: self)

    override public func providesSettingsView() -> Bool { true }
    override public func settingsView() -> AnyView { AnyView(MathExpressionView(model: _settingsModel)) }
    override public var settingsSize: SettingsViewSize
    {
        // Compact for the single-line field; wide + tall for the code editor.
        _settingsModel.showsCode
            ? .Custom(size: CGSize(width: 760, height: 540))
            : .Custom(size: CGSize(width: 480, height: 210))
    }

    // MARK: - Compilation & port sync

    private func compileAndSync()
    {
        let result = compile(self.stringExpression)
        self.compiled = result

        // Only re-derive ports from a valid compile, so a half-typed expression
        // doesn't tear down ports (and their wires) mid-edit.
        if result.isValid
        {
            self.portInterface = result.interface
            self.syncPorts(to: result.interface)
            self.needsEvaluation = true
        }

        let hasError = result.diagnostics.contains { $0.severity == .error }
        // Multi-statement expressions span several lines; collapse newlines to
        // spaces so the single-line node title reads cleanly.
        let title = self.stringExpression.replacingOccurrences(of: "\n", with: " ")
        self.evaluatedDisplayName = hasError ? "⚠ \(title)" : title

        self._settingsModel.diagnostics = result.diagnostics
        self.nameSubject.send()
    }

    /// Diff the compiled interface against the current dynamic ports, adding,
    /// removing, and retyping to match. A port whose name *and* type are
    /// unchanged is left completely untouched, so its wires survive. On a
    /// genuine retype, wires the new type can still accept are re-established;
    /// the rest are dropped.
    private func syncPorts(to interface: Interface)
    {
        self.syncPorts(desired: interface.inputs.map { ($0.name, $0.type) },
                       existing: self.inputPorts(),
                       kind: .Inlet)
        self.syncPorts(desired: interface.outputs.map { ($0.name, $0.type) },
                       existing: self.outputPorts(),
                       kind: .Outlet)
    }

    private func syncPorts(desired: [(name: String, type: ValueType)], existing: [Port], kind: PortKind)
    {
        let desiredNames = Set(desired.map(\.name))
        var existingByName: [String: Port] = [:]
        for port in existing { existingByName[port.name] = port }

        // Remove ports the expression no longer references.
        for port in existing where !desiredNames.contains(port.name)
        {
            self.removePort(port)
        }

        // Add new ports, and retype ports whose type changed.
        for (portName, valueType) in desired
        {
            let wantType = EnginePortMarshalling.portType(for: valueType)

            if let port = existingByName[portName]
            {
                if port.portType == wantType { continue } // unchanged — keep wires

                // Retype: preserve connections the new type can still accept.
                let survivors = port.connections.filter { wantType.canConnect(to: $0.portType) }
                self.removePort(port) // disconnects everything
                let replacement = self.makePort(name: portName, type: valueType, kind: kind)
                self.addDynamicPort(replacement, name: portName)
                for other in survivors { replacement.connect(to: other) }
            }
            else
            {
                self.addDynamicPort(self.makePort(name: portName, type: valueType, kind: kind), name: portName)
            }
        }
    }

    private func makePort(name: String, type: ValueType, kind: PortKind) -> Port
    {
        kind == .Inlet
            ? EnginePortMarshalling.makeInputPort(name: name, type: type)
            : EnginePortMarshalling.makeOutputPort(name: name, type: type)
    }

    // MARK: - Execution

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let compiled = self.compiled, compiled.isValid else { return }

        let inlets = self.inputPorts()
        let inputsChanged = inlets.contains { $0.valueDidChange }
        guard inputsChanged || self.needsEvaluation else { return }
        self.needsEvaluation = false

        // Gather the inputs the interface declares. An input with no value yet
        // (upstream not propagated) is simply absent — the engine then throws
        // `.missingInput`, which we treat as "don't emit yet", exactly like the
        // previous node's unresolved-variable guard.
        var inputs: [String: EngineValue] = [:]
        for input in self.portInterface.inputs
        {
            guard let port = self.findPort(named: input.name, as: Port.self) else { continue }
            if let value = EnginePortMarshalling.readEngineValue(from: port, as: input.type)
            {
                inputs[input.name] = value
            }
        }

        let outputs: [EngineValue]
        do
        {
            outputs = try compiled.evaluateValues(with: inputs)
        }
        catch
        {
            // .missingInput (input not propagated yet), .indexOutOfBounds,
            // .limitExceeded, .notCompiled — skip this frame's emit.
            return
        }

        for (index, output) in self.portInterface.outputs.enumerated()
        {
            guard index < outputs.count else { break }
            let value = outputs[index]
            // Scrub non-finite results (0/0, log(-1), asin out of range, …)
            // exactly as the previous node did — skip rather than emit garbage.
            guard EnginePortMarshalling.isFinite(value) else { continue }
            guard let port = self.findPort(named: output.name, as: Port.self) else { continue }
            EnginePortMarshalling.send(value, to: port)
        }
    }
}
