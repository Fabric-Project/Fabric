//
//  MathExpressionParametricGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 6/19/26.
//

import Foundation
import Satin
import Metal
import SwiftUI
import simd
import MathExpressionEngine

// MARK: - Settings View

struct MathExpressionParametricView: View
{
    @Bindable var model: MathExpressionParametricGeometryNode.SettingsModel

    var body: some View
    {
        VStack(alignment: .leading, spacing: 8)
        {
            Text("Define a parametric surface as X(u,v), Y(u,v), Z(u,v). u and v are the parametric parameters. Any other variables (e.g. a, b) become input ports.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            expressionRow(label: "X =", text: $model.expressionX, valid: model.statusX)
            expressionRow(label: "Y =", text: $model.expressionY, valid: model.statusY)
            expressionRow(label: "Z =", text: $model.expressionZ, valid: model.statusZ)
        }
        .padding(10)
    }

    @ViewBuilder
    private func expressionRow(label: String, text: Binding<String>, valid: Bool) -> some View
    {
        HStack(spacing: 4)
        {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 28, alignment: .trailing)
            TextField("Expression", text: text)
                .font(.system(size: 10, design: .monospaced))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .foregroundStyle(valid ? Color.primary : Color.red)
        }
    }
}

// MARK: - Settings

public struct ParametricExpressionSettings: NodeSettings
{
    public var expressionX: String
    public var expressionY: String
    public var expressionZ: String

    public init(expressionX: String, expressionY: String, expressionZ: String)
    {
        self.expressionX = expressionX
        self.expressionY = expressionY
        self.expressionZ = expressionZ
    }
}

// MARK: - Node

public class MathExpressionParametricGeometryNode: BaseGeometryNode
{
    public override class var name: String { "Parametric Expression Geometry" }
    public override class var nodeDescription: String { "Define a parametric surface by writing X(u,v), Y(u,v), Z(u,v) math expressions. Extra variables become wirable input ports." }

    // Default expressions: unit sphere
    class var defaultExpressionX: String { "cos(u) * sin(v)" }
    class var defaultExpressionY: String { "sin(u) * sin(v)" }
    class var defaultExpressionZ: String { "cos(v)" }

    // u and v are always resolved by the generator; they never become ports.
    private static let parametricBindings: Set<String> = ["u", "v"]

    /// Shown as the node's title: the three axis expressions. Falls back to the
    /// type name when all axes are blank; a user `userName` overrides it.
    /// Refreshed via namingDidChange() in parseExpressions().
    override public func deriveSubtitle() -> String? {
        let axes = [expressionX, expressionY, expressionZ]
        guard axes.contains(where: { !$0.isEmpty }) else { return nil }
        // Collapse newlines to spaces so the single-line node title reads cleanly.
        return axes.joined(separator: ", ").replacingOccurrences(of: "\n", with: " ")
    }

    /// An axis that fails to compile is the node's status, naming the failing
    /// axes. Worded once, in updateCompileErrorStatus(): execute() throws this
    /// same message, so the glyph and the thrown error cannot drift apart.
    override public func deriveStatuses() -> [NodeStatus] { compileErrorStatus.map { [$0] } ?? [] }
    private var compileErrorStatus: NodeStatus?

    // MARK: - Settings Model

    @MainActor
    @Observable final class SettingsModel
    {
        var expressionX: String
        {
            didSet
            {
                guard let node, expressionX != node.expressionX else { return }
                node.setSettings(ParametricExpressionSettings(expressionX: expressionX, expressionY: node.expressionY, expressionZ: node.expressionZ))
            }
        }
        var expressionY: String
        {
            didSet
            {
                guard let node, expressionY != node.expressionY else { return }
                node.setSettings(ParametricExpressionSettings(expressionX: node.expressionX, expressionY: expressionY, expressionZ: node.expressionZ))
            }
        }
        var expressionZ: String
        {
            didSet
            {
                guard let node, expressionZ != node.expressionZ else { return }
                node.setSettings(ParametricExpressionSettings(expressionX: node.expressionX, expressionY: node.expressionY, expressionZ: expressionZ))
            }
        }

        var statusX: Bool
        var statusY: Bool
        var statusZ: Bool

        private weak var node: MathExpressionParametricGeometryNode?

        init(node: MathExpressionParametricGeometryNode)
        {
            self.node = node
            self.expressionX = node.expressionX
            self.expressionY = node.expressionY
            self.expressionZ = node.expressionZ
            let axes = node.validAxes
            self.statusX = axes.x
            self.statusY = axes.y
            self.statusZ = axes.z
        }

        func refreshFromNode()
        {
            guard let node else { return }
            if expressionX != node.expressionX { expressionX = node.expressionX }
            if expressionY != node.expressionY { expressionY = node.expressionY }
            if expressionZ != node.expressionZ { expressionZ = node.expressionZ }
            let axes = node.validAxes
            statusX = axes.x
            statusY = axes.y
            statusZ = axes.z
        }
    }

    /// Nil until a settings view asks for it.
    private var _settingsModelStorage: SettingsModel?

    override public func refreshSettingsModel()
    {
        super.refreshSettingsModel()
        _settingsModelStorage?.refreshFromNode()
    }

    var settingsModel: SettingsModel
    {
        performOnMainSync
        {
            if let model = _settingsModelStorage { return model }
            let model = SettingsModel(node: self)
            _settingsModelStorage = model
            return model
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey
    {
        case expressionX, expressionY, expressionZ
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.expressionX = try container.decodeIfPresent(String.self, forKey: .expressionX) ?? Self.defaultExpressionX
        self.expressionY = try container.decodeIfPresent(String.self, forKey: .expressionY) ?? Self.defaultExpressionY
        self.expressionZ = try container.decodeIfPresent(String.self, forKey: .expressionZ) ?? Self.defaultExpressionZ
        try super.init(from: decoder)
        parseExpressions()
    }

    override public var settings: (any NodeSettings)?
    {
        ParametricExpressionSettings(expressionX: expressionX, expressionY: expressionY, expressionZ: expressionZ)
    }

    /// Parses once for the three axes, so a variable moving between axes keeps its port.
    override public func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? ParametricExpressionSettings else { return }
        self.isApplyingSettings = true
        self.expressionX = settings.expressionX
        self.expressionY = settings.expressionY
        self.expressionZ = settings.expressionZ
        self.isApplyingSettings = false
        self.parseExpressions()
        super.apply(settings)
    }

    private var isApplyingSettings = false

    public required init(context: Context)
    {
        self.expressionX = Self.defaultExpressionX
        self.expressionY = Self.defaultExpressionY
        self.expressionZ = Self.defaultExpressionZ
        super.init(context: context)
        parseExpressions()
    }

    public init(context: Context, settings: ParametricExpressionSettings)
    {
        self.expressionX = settings.expressionX
        self.expressionY = settings.expressionY
        self.expressionZ = settings.expressionZ
        super.init(context: context)
        parseExpressions()
    }

    // MARK: - Static Ports

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)
        return [
            ("inputResolutionU", ParameterPort(parameter: IntParameter("Resolution U",  128,  .inputfield, "Mesh segments along the U direction"))),
            ("inputResolutionV", ParameterPort(parameter: IntParameter("Resolution V",  128,  .inputfield, "Mesh segments along the V direction"))),
            ("inputRangeUMin",   ParameterPort(parameter: FloatParameter("Range U Min", -.pi, .inputfield, "Lower bound of the U parameter domain"))),
            ("inputRangeUMax",   ParameterPort(parameter: FloatParameter("Range U Max",  .pi, .inputfield, "Upper bound of the U parameter domain"))),
            ("inputRangeVMin",   ParameterPort(parameter: FloatParameter("Range V Min",    0, .inputfield, "Lower bound of the V parameter domain"))),
            ("inputRangeVMax",   ParameterPort(parameter: FloatParameter("Range V Max",  .pi, .inputfield, "Upper bound of the V parameter domain"))),
        ] + ports
    }

    public var inputResolutionU: ParameterPort<Int> { _inputResolutionU }
    private var _inputResolutionU: ParameterPort<Int>!
    public var inputResolutionV: ParameterPort<Int> { _inputResolutionV }
    private var _inputResolutionV: ParameterPort<Int>!
    public var inputRangeUMin: ParameterPort<Float> { _inputRangeUMin }
    private var _inputRangeUMin: ParameterPort<Float>!
    public var inputRangeUMax: ParameterPort<Float> { _inputRangeUMax }
    private var _inputRangeUMax: ParameterPort<Float>!
    public var inputRangeVMin: ParameterPort<Float> { _inputRangeVMin }
    private var _inputRangeVMin: ParameterPort<Float>!
    public var inputRangeVMax: ParameterPort<Float> { _inputRangeVMax }
    private var _inputRangeVMax: ParameterPort<Float>!

    override public func bindPorts()
    {
        super.bindPorts()
        self.variablePorts = _dynamicVariablePortNames.sorted().compactMap { name in
            (findPort(named: name) as ParameterPort<Float>?).map { (name, $0) }
        }
        self._inputResolutionU = findPort(named: "inputResolutionU")
        self._inputResolutionV = findPort(named: "inputResolutionV")
        self._inputRangeUMin = findPort(named: "inputRangeUMin")
        self._inputRangeUMax = findPort(named: "inputRangeUMax")
        self._inputRangeVMin = findPort(named: "inputRangeVMin")
        self._inputRangeVMax = findPort(named: "inputRangeVMax")
    }

    // MARK: - Geometry

    public override var geometry: ParametricGeometry { _geometry }

    private lazy var _geometry: ParametricGeometry = ParametricGeometry(
        context: self.context,
        rangeU: -.pi ... .pi,
        rangeV: 0 ... .pi,
        resolution: simd_int2(128, 128),
        generator: { _, _ in .zero }
    )

    // MARK: - Expression Parsing

    internal var expressionX: String
    {
        didSet
        {
            guard oldValue != expressionX, !isApplyingSettings else { return }
            parseExpressions()
        }
    }
    internal var expressionY: String
    {
        didSet
        {
            guard oldValue != expressionY, !isApplyingSettings else { return }
            parseExpressions()
        }
    }
    internal var expressionZ: String
    {
        didSet
        {
            guard oldValue != expressionZ, !isApplyingSettings else { return }
            parseExpressions()
        }
    }

    private struct AxisExpression
    {
        let compileResult: CompileResult

        var variableNames: Set<String>
        {
            Set(compileResult.interface.inputs.map(\.name))
        }

        func evaluate(inputs: [String: Float]) -> Float
        {
            (try? compileResult.evaluate(inputs)) ?? 0
        }
    }

    private var evalX: AxisExpression? = nil
    private var evalY: AxisExpression? = nil
    private var evalZ: AxisExpression? = nil
    private var _expressionsDirty: Bool = true

    // Names of dynamically-added variable ports (excludes static ports).
    private var _dynamicVariablePortNames: Set<String> = []

    private func parseExpressions()
    {
        evalX = axisExpression(from: expressionX)
        evalY = axisExpression(from: expressionY)
        evalZ = axisExpression(from: expressionZ)

        updateCompileErrorStatus()
        syncVariablePorts()
        _expressionsDirty = true
        namingDidChange()
        settingsDidChange()
    }

    /// Which axes compile.
    var validAxes: (x: Bool, y: Bool, z: Bool) { (evalX != nil, evalY != nil, evalZ != nil) }

    /// Blank everywhere is a node not yet written rather than one that fails,
    /// and reports nothing, as deriveSubtitle() also has it. Such a node still
    /// cannot run; execute() has its own wording for that.
    private func updateCompileErrorStatus()
    {
        let failing = zip(["X", "Y", "Z"], [evalX, evalY, evalZ])
            .filter { $0.1 == nil }
            .map(\.0)

        guard [expressionX, expressionY, expressionZ].contains(where: { !$0.isEmpty }),
              !failing.isEmpty
        else
        {
            compileErrorStatus = nil
            return
        }

        let axes = failing.joined(separator: ", ")
        compileErrorStatus = .error("\(axes) expression\(failing.count == 1 ? " does" : "s do") not compile to a single float output.")
    }

    private func axisExpression(from source: String) -> AxisExpression?
    {
        let compileResult = compile(source)
        guard compileResult.isValid,
              compileResult.interface.outputs.count == 1,
              compileResult.interface.outputs.first?.type == .float,
              compileResult.interface.inputs.allSatisfy({ $0.type == .float })
        else
        {
            return nil
        }

        return AxisExpression(compileResult: compileResult)
    }

    /// One Float inlet per free variable across the three expressions, minus u
    /// and v which the generator resolves, after the node's own ports.
    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + _dynamicVariablePortNames.sorted().map { name in
            PortDeclaration(key: name, portType: .Float, kind: .Inlet, name: name)
        }
    }

    /// Each variable's inlet, in declared order.
    private var variablePorts: [(name: String, port: ParameterPort<Float>)] = []

    private func syncVariablePorts()
    {
        var allVars = Set<String>()
        if let ev = evalX { allVars.formUnion(ev.variableNames) }
        if let ev = evalY { allVars.formUnion(ev.variableNames) }
        if let ev = evalZ { allVars.formUnion(ev.variableNames) }

        _dynamicVariablePortNames = allVars.subtracting(Self.parametricBindings)
        self.reconcilePorts()
    }

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView
    {
        performOnMainSync { AnyView(MathExpressionParametricView(model: settingsModel)) }
    }

    override public var settingsSize: SettingsViewSize { .Medium }

    // MARK: - Evaluate

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard evalX != nil, evalY != nil, evalZ != nil else
        {
            throw FabricError(.execution(.syntax),
                              severity: .recoverable,
                              message: compileErrorStatus?.message
                                       ?? "Parametric geometry needs an expression for X, Y and Z.")
        }

        try super.execute(renderer: renderer,
                          executionInfo: executionInfo,
                          renderPassDescriptor: renderPassDescriptor,
                          commandBuffer: commandBuffer)
    }

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        let paramsChanged = inputResolutionU.valueDidChange || inputResolutionV.valueDidChange
            || inputRangeUMin.valueDidChange || inputRangeUMax.valueDidChange
            || inputRangeVMin.valueDidChange || inputRangeVMax.valueDidChange

        let anyVarChanged = variablePorts.contains { $0.port.valueDidChange }

        if paramsChanged || _expressionsDirty || anyVarChanged
        {
            let resU = Int32(inputResolutionU.value ?? 128)
            let resV = Int32(inputResolutionV.value ?? 128)
            let uMin = inputRangeUMin.value ?? -.pi
            let uMax = inputRangeUMax.value ??  .pi
            let vMin = inputRangeVMin.value ??   0
            let vMax = inputRangeVMax.value ??  .pi

            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = min(uMin, uMax) ... max(uMin, uMax)
            geo.rangeV = min(vMin, vMax) ... max(vMin, vMax)

            // Snapshot variable port values so the generator closure is pure.
            var varSnapshot: [String: Float] = [:]
            for (name, port) in variablePorts
            {
                varSnapshot[name] = port.value ?? 0
            }

            let eX = evalX, eY = evalY, eZ = evalZ
            geo.generator = { u, v in
                var inputs = varSnapshot
                inputs["u"] = u
                inputs["v"] = v

                let x = eX?.evaluate(inputs: inputs) ?? 0
                let y = eY?.evaluate(inputs: inputs) ?? 0
                let z = eZ?.evaluate(inputs: inputs) ?? 0
                let result = simd_make_float3(x, y, z)
                return result.x.isFinite && result.y.isFinite && result.z.isFinite ? result : .zero
            }

            _expressionsDirty = false
            shouldOutput = true
        }

        return shouldOutput
    }
}
