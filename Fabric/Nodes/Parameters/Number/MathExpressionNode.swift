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

// MARK: - Settings View

struct MathExpressionView: View
{
    @Bindable var model: MathExpressionNode.SettingsModel

    var body: some View
    {
        VStack(alignment: .leading, spacing: 8)
        {
            Text("Write an expression and the node derives its ports: free names become typed inputs, `out name = …` becomes outputs. Supports numbers, vectors, transforms, quaternions and arrays (comprehensions).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $model.stringExpression)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 54)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
                .autocorrectionDisabled(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            diagnostics
        }
        .padding(10)
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
    override public var name: String { evaluatedDisplayName }
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
    override public var settingsSize: SettingsViewSize { .Medium }

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
        self.evaluatedDisplayName = hasError ? "⚠ \(self.stringExpression)" : self.stringExpression

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
