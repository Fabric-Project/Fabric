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
internal import MathParser

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

    // MARK: - Settings Model

    @Observable final class SettingsModel
    {
        var expressionX: String
        {
            didSet
            {
                guard expressionX != node?.expressionX else { return }
                node?.expressionX = expressionX
            }
        }
        var expressionY: String
        {
            didSet
            {
                guard expressionY != node?.expressionY else { return }
                node?.expressionY = expressionY
            }
        }
        var expressionZ: String
        {
            didSet
            {
                guard expressionZ != node?.expressionZ else { return }
                node?.expressionZ = expressionZ
            }
        }

        var statusX: Bool = true
        var statusY: Bool = true
        var statusZ: Bool = true

        private weak var node: MathExpressionParametricGeometryNode?

        init(node: MathExpressionParametricGeometryNode)
        {
            self.node = node
            self.expressionX = node.expressionX
            self.expressionY = node.expressionY
            self.expressionZ = node.expressionZ
        }
    }

    internal lazy var _settingsModel: SettingsModel = SettingsModel(node: self)

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

    public override func encode(to encoder: any Encoder) throws
    {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(expressionX, forKey: .expressionX)
        try container.encode(expressionY, forKey: .expressionY)
        try container.encode(expressionZ, forKey: .expressionZ)
    }

    public required init(context: Context)
    {
        self.expressionX = Self.defaultExpressionX
        self.expressionY = Self.defaultExpressionY
        self.expressionZ = Self.defaultExpressionZ
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

    public var inputResolutionU: ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV: ParameterPort<Int>   { port(named: "inputResolutionV") }
    public var inputRangeUMin:   ParameterPort<Float> { port(named: "inputRangeUMin") }
    public var inputRangeUMax:   ParameterPort<Float> { port(named: "inputRangeUMax") }
    public var inputRangeVMin:   ParameterPort<Float> { port(named: "inputRangeVMin") }
    public var inputRangeVMax:   ParameterPort<Float> { port(named: "inputRangeVMax") }

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
            guard oldValue != expressionX else { return }
            parseExpressions()
        }
    }
    internal var expressionY: String
    {
        didSet
        {
            guard oldValue != expressionY else { return }
            parseExpressions()
        }
    }
    internal var expressionZ: String
    {
        didSet
        {
            guard oldValue != expressionZ else { return }
            parseExpressions()
        }
    }

    private let mathParser = MathParser()
    private var evalX: Evaluator? = nil
    private var evalY: Evaluator? = nil
    private var evalZ: Evaluator? = nil
    private var _expressionsDirty: Bool = true

    // Names of dynamically-added variable ports (excludes static ports).
    private var _dynamicVariablePortNames: Set<String> = []

    private func parseExpressions()
    {
        switch mathParser.parseResult(expressionX) {
        case .success(let ev): evalX = ev; _settingsModel.statusX = true
        case .failure:         evalX = nil; _settingsModel.statusX = false
        }
        switch mathParser.parseResult(expressionY) {
        case .success(let ev): evalY = ev; _settingsModel.statusY = true
        case .failure:         evalY = nil; _settingsModel.statusY = false
        }
        switch mathParser.parseResult(expressionZ) {
        case .success(let ev): evalZ = ev; _settingsModel.statusZ = true
        case .failure:         evalZ = nil; _settingsModel.statusZ = false
        }

        syncVariablePorts()
        _expressionsDirty = true
        nameSubject.send()
    }

    /// Keeps dynamic input ports in sync with the union of free variables across all
    /// three expressions, minus u and v which are always resolved by the generator.
    private func syncVariablePorts()
    {
        var allVars = Set<String>()
        if let ev = evalX { allVars.formUnion(ev.unresolved.variables.map { String($0) }) }
        if let ev = evalY { allVars.formUnion(ev.unresolved.variables.map { String($0) }) }
        if let ev = evalZ { allVars.formUnion(ev.unresolved.variables.map { String($0) }) }

        let variableNames = allVars.subtracting(Self.parametricBindings)

        for name in _dynamicVariablePortNames.subtracting(variableNames)
        {
            if let port: Port = self.findPort(named: name)
            {
                self.removePort(port)
            }
            _dynamicVariablePortNames.remove(name)
        }

        for name in variableNames.subtracting(_dynamicVariablePortNames)
        {
            self.addDynamicPort(
                ParameterPort(parameter: FloatParameter(name, 0.0, .inputfield)),
                name: name
            )
            _dynamicVariablePortNames.insert(name)
        }
    }

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView
    {
        AnyView(MathExpressionParametricView(model: _settingsModel))
    }

    override public var settingsSize: SettingsViewSize { .Medium }

    // MARK: - Evaluate

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        let paramsChanged = inputResolutionU.valueDidChange || inputResolutionV.valueDidChange
            || inputRangeUMin.valueDidChange || inputRangeUMax.valueDidChange
            || inputRangeVMin.valueDidChange || inputRangeVMax.valueDidChange

        let anyVarChanged = _dynamicVariablePortNames.contains { name in
            (self.findPort(named: name) as? ParameterPort<Float>)?.valueDidChange == true
        }

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
            var varSnapshot: [String: Double] = [:]
            for name in _dynamicVariablePortNames
            {
                let value = (self.findPort(named: name) as? ParameterPort<Float>)?.value ?? 0
                varSnapshot[name] = Double(value)
            }

            let eX = evalX, eY = evalY, eZ = evalZ
            geo.generator = { u, v in
                let vars = { (name: String) -> Double? in
                    switch name {
                    case "u": return Double(u)
                    case "v": return Double(v)
                    default:  return varSnapshot[name]
                    }
                }
                let x = Float(eX?.eval(variables: vars) ?? 0)
                let y = Float(eY?.eval(variables: vars) ?? 0)
                let z = Float(eZ?.eval(variables: vars) ?? 0)
                let result = simd_make_float3(x, y, z)
                return result.x.isFinite && result.y.isFinite && result.z.isFinite ? result : .zero
            }

            _expressionsDirty = false
            shouldOutput = true
        }

        return shouldOutput
    }
}
