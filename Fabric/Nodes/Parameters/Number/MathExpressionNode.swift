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
import MathExpressionEditorSupport
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
    @State private var languageService = MathExpressionLanguageService()
    @State private var editorMessages: Set<TextLocated<Message>> = []

    private var isMultiStatement: Bool
    {
        model.stringExpression.contains(";") || model.stringExpression.contains("\n")
    }

    var body: some View
    {
        VStack(alignment: .leading, spacing: 8)
        {
            CodeEditorGuidance(
                "Write an expression — free names become input ports, results become output ports. Beyond numbers, values can be vectors, transforms or arrays, and a single expression can drive several named inputs and outputs at once.",
                guide: "[Language guide ↗](https://github.com/Fabric-Project/MathExpressionEngine/blob/main/GUIDE.md)")

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
                   language: .mathExpressionLanguage(self.languageService))
            .codeEditorChrome()
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

// MARK: - Settings

public struct MathExpressionSettings: NodeSettings
{
    public var stringExpression: String

    public init(stringExpression: String)
    {
        self.stringExpression = stringExpression
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

    /// Shown as the node's title: the salient part of the expression. nil
    /// (empty) falls back to the type name; a user `userName` overrides this.
    override public func deriveSubtitle() -> String? { evaluatedSubtitle }
    private var evaluatedSubtitle: String = ""

    /// A compile error is the node's status, with the diagnostics as the
    /// message. Worded once, in compileAndSync(): execute() throws this same
    /// message, so the glyph and the thrown error cannot drift apart.
    override public func deriveStatuses() -> [NodeStatus] { compileErrorStatus.map { [$0] } ?? [] }
    private var compileErrorStatus: NodeStatus?

    /// Stands in when a compile fails without saying why.
    private static let invalidExpressionMessage = "Math expression is invalid."

    /// Extracts the salient part of a (possibly multi-statement) expression for
    /// use as the node title. A leading `//` comment is taken verbatim as an
    /// author-supplied title. Otherwise `in` input declarations and `let` locals
    /// are dropped, `//` comments stripped, and the right-hand side of the first
    /// output (`out …`) — or, failing that, the first assignment — is used, so
    /// `in spectrum:float[]; out scales = <expr>` titles as `<expr>`. A bare
    /// expression (no assignment) is kept as-is. Per the language, only `;`
    /// separates statements; newlines are whitespace, so they are normalised out.
    static func salientTitle(from expression: String) -> String
    {
        // A leading comment is the author's own title — use it verbatim (sans `//`).
        let leading = expression.drop(while: \.isWhitespace)
        if leading.hasPrefix("//")
        {
            let firstLine = leading.prefix { $0 != "\n" }
            let commentText = firstLine.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if !commentText.isEmpty { return commentText }
        }

        // Comments run to end of line, so strip them line-by-line first. What
        // remains is joined with spaces (newlines are just whitespace) and then
        // split into statements on `;`, with interior whitespace normalised.
        let statements = expression
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                if let comment = line.firstRange(of: "//") { return line[..<comment.lowerBound] }
                return line
            }
            .joined(separator: " ")
            .split(separator: ";")
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }

        // First whitespace/`:`-delimited token — identifies `in`/`let`/`out`.
        func head(_ statement: String) -> String
        {
            String(statement.prefix { $0 != " " && $0 != ":" })
        }

        // Drop input declarations and locals; they carry no result. Input
        // declarations with a default value are held back as a last resort only
        // — they must never outrank an actual output or bare expression.
        let meaningful = statements.filter { statement in
            switch head(statement)
            {
            case "let", "in": return false
            default:          return true
            }
        }
        let inputDefaults = statements.filter {
            head($0) == "in" && assignmentIndex(in: $0) != nil
        }

        // RHS of the first standalone `=`, or nil if the statement has none.
        func assignmentRHS(_ statement: String) -> String?
        {
            guard let eq = assignmentIndex(in: statement) else { return nil }
            let rhs = statement[statement.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
            return rhs.isEmpty ? nil : rhs
        }

        // Prefer the RHS of the first output, else of the first assignment.
        let outputs = meaningful.filter { head($0) == "out" }
        for statement in outputs + meaningful
        {
            if let rhs = assignmentRHS(statement) { return rhs }
        }

        // A bare expression (no assignment).
        let bare = meaningful.joined(separator: "; ")
        if !bare.isEmpty { return bare }

        // Only declarations remain: fall back to an input default's value.
        // Empty when there is none, so the call site falls back to the type name.
        for statement in inputDefaults
        {
            if let rhs = assignmentRHS(statement) { return rhs }
        }
        return ""
    }

    /// Index of the first standalone `=` (assignment), skipping `==`/`<=`/`>=`/`!=`.
    private static func assignmentIndex(in statement: String) -> String.Index?
    {
        var idx = statement.startIndex
        while idx < statement.endIndex
        {
            if statement[idx] == "="
            {
                let prev = idx > statement.startIndex ? statement[statement.index(before: idx)] : " "
                let afterIdx = statement.index(after: idx)
                let next = afterIdx < statement.endIndex ? statement[afterIdx] : " "
                if !"!<>=".contains(prev) && next != "=" { return idx }
            }
            idx = statement.index(after: idx)
        }
        return nil
    }

    // MARK: - State

    var stringExpression: String
    {
        didSet
        {
            guard oldValue != stringExpression else { return }
            self.compileAndSync()
        }
    }

    override public var compilableSource: String? { self.stringExpression }

    /// The last compile. Recomputed only when `stringExpression` changes.
    private var compiled: CompileResult?

    /// The last compile's diagnostics.
    var compileDiagnostics: [Diagnostic] { compiled?.diagnostics ?? [] }

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

    override public var settings: (any NodeSettings)? { MathExpressionSettings(stringExpression: self.stringExpression) }

    override public func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? MathExpressionSettings else { return }
        self.stringExpression = settings.stringExpression
        super.apply(settings)
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

    public convenience init(context: Context, settings: MathExpressionSettings)
    {
        self.init(context: context, expression: settings.stringExpression)
    }

    // MARK: - Settings

    @MainActor
    @Observable final class SettingsModel
    {
        var stringExpression: String
        {
            didSet
            {
                guard stringExpression != node?.stringExpression else { return }
                node?.setSettings(MathExpressionSettings(stringExpression: stringExpression))
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
            self.diagnostics = node.compileDiagnostics
        }

        func refreshFromNode()
        {
            guard let node else { return }
            if stringExpression != node.stringExpression { stringExpression = node.stringExpression }
            diagnostics = node.compileDiagnostics
        }
    }

    /// Nil until a settings view, or settingsSize, asks for it.
    private var _settingsModelStorage: SettingsModel?

    override public func refreshSettingsModel()
    {
        super.refreshSettingsModel()
        _settingsModelStorage?.refreshFromNode()
    }

    internal var _settingsModel: SettingsModel
    {
        performOnMainSync
        {
            if let model = _settingsModelStorage { return model }
            let model = SettingsModel(node: self)
            _settingsModelStorage = model
            return model
        }
    }

    override public func providesSettingsView() -> Bool { true }
    override public func settingsView() -> AnyView { performOnMainSync { AnyView(MathExpressionView(model: _settingsModel)) } }
    override public var settingsSize: SettingsViewSize
    {
        // Compact for the single-line field; wide + tall for the code editor.
        performOnMainSync { _settingsModel.showsCode }
            ? .Custom(size: CGSize(width: 760, height: 540))
            : .Custom(size: CGSize(width: 480, height: 210))
    }

    // MARK: - Compilation & port sync

    private func compileAndSync()
    {
        // `needsEvaluation` only reaches the node once the renderer runs it, and
        // a Processor that is not dirty is skipped. Nothing upstream of an edit
        // moves, so the node asks for itself.
        self.markDirty()

        let result = compile(self.stringExpression)
        self.compiled = result

        // Only re-derive ports from a valid compile, so a half-typed expression
        // doesn't tear down ports (and their wires) mid-edit.
        if result.isValid
        {
            self.portInterface = result.interface
            self.lastCompiledSource = self.stringExpression
            self.reconcilePorts()
            self.needsEvaluation = true
        }
        // An expression that does not compile on open would leave the node
        // with no ports; the last one that compiled declares them instead,
        // for its interface only. `compiled` stays the failing one, so the
        // node does not evaluate until its own expression compiles.
        else if self.portInterface.inputs.isEmpty && self.portInterface.outputs.isEmpty,
                let fallback = self.interfaceFallbackSource
        {
            let fallbackResult = compile(fallback)
            if fallbackResult.isValid
            {
                self.portInterface = fallbackResult.interface
                self.reconcilePorts()
            }
        }

        self.evaluatedSubtitle = Self.salientTitle(from: self.stringExpression)

        let errors = result.diagnostics.filter { $0.severity == .error }
        self.compileErrorStatus = result.isValid && errors.isEmpty
            ? nil
            : .error(errors.isEmpty
                     ? Self.invalidExpressionMessage
                     : errors.map(\.message).joined(separator: "\n"))

        self.settingsDidChange()
        self.namingDidChange()
    }

    /// The ports of the last valid compile: its inputs then its outputs, each
    /// under its name. A port whose name and type are unchanged keeps its
    /// wires; a retyped one keeps those the new type accepts.
    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts()
            + self.portInterface.inputs.map { self.declaration(name: $0.name, type: $0.type, kind: .Inlet) }
            + self.portInterface.outputs.map { self.declaration(name: $0.name, type: $0.type, kind: .Outlet) }
    }

    /// The interface's inputs, each with a reader of its port, and its
    /// outputs' writers by output index.
    private var boundInputs: [(name: String, read: () -> EngineValue?)] = []
    private var boundOutputs: [((EngineValue) -> Void)?] = []

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputs = self.portInterface.inputs.compactMap { input in
            guard let port: Port = findPort(named: input.name),
                  let read = EnginePortMarshalling.reader(for: port, as: input.type)
            else { return nil }
            return (input.name, read)
        }
        self.boundOutputs = self.portInterface.outputs.map { output in
            (findPort(named: output.name) as Port?).flatMap { EnginePortMarshalling.writer(for: $0, as: output.type) }
        }
    }

    private func declaration(name: String, type: ValueType, kind: PortKind) -> PortDeclaration
    {
        PortDeclaration(key: name, portType: EnginePortMarshalling.portType(for: type), kind: kind, name: name)
    }

    // MARK: - Execution

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let compiled = self.compiled, compiled.isValid else
        {
            throw FabricError(.execution(.syntax),
                              severity: .recoverable,
                              message: self.compileErrorStatus?.message ?? Self.invalidExpressionMessage)
        }

        let inlets = self.inputPorts()
        let inputsChanged = inlets.contains { $0.valueDidChange }
        guard inputsChanged || self.needsEvaluation else { return }
        self.needsEvaluation = false

        // Gather the inputs the interface declares. An input with no value yet
        // (upstream not propagated) is simply absent — the engine then throws
        // `.missingInput`, which we treat as "don't emit yet", exactly like the
        // previous node's unresolved-variable guard.
        var inputs: [String: EngineValue] = [:]
        for (name, read) in self.boundInputs
        {
            if let value = read() { inputs[name] = value }
        }

        let outputs: [EngineValue]
        do
        {
            outputs = try compiled.evaluateValues(with: inputs)
        }
        catch
        {
            // A missing input is transient — upstream hasn't propagated yet —
            // so skip this frame's emit. The remaining cases are faults in the
            // expression and are reported.
            if case .missingInput = error { return }

            throw FabricError(.execution(.syntax),
                              severity: .recoverable,
                              message: error.localizedDescription,
                              underlyingError: error)
        }

        for (index, write) in self.boundOutputs.enumerated()
        {
            guard index < outputs.count else { break }
            let value = outputs[index]
            // Scrub non-finite results (0/0, log(-1), asin out of range, …)
            // exactly as the previous node did — skip rather than emit garbage.
            guard EnginePortMarshalling.isFinite(value) else { continue }
            write?(value)
        }
    }
}
