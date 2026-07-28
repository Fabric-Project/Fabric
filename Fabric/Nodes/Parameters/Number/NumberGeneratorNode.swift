//
//  NumberGeneratorNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal
import SwiftUI

/// How the Number Generator produces its next value on each trigger. Modes expose
/// different parameter ports, so this lives on the Settings picker (a
/// StrategyNode strategy) rather than a wired port.
public enum NumberGeneratorMode: String, NodeStrategyOption, CaseIterable
{
    /// Independent draws, optionally shaped by a distribution.
    case random = "Random"
    /// A low-discrepancy sequence that spreads evenly and never clumps.
    case evenSpread = "Even Spread"
    /// A bounded random walk from the current value.
    case walk = "Walk"

    /// One or two sentences shown in the Settings pane to explain the mode.
    public var usageGuidance: String
    {
        switch self
        {
        case .random:
            return "Independent draws each trigger. Distribution shapes them — Uniform is flat, Gaussian clusters around the middle, Triangular peaks there — and Minimum Change forces consecutive values apart."
        case .evenSpread:
            return "A low-discrepancy (golden-ratio) sequence: values look random but never clump, covering the range evenly over time. Distribution reshapes that even coverage into the chosen curve."
        case .walk:
            return "A random walk: each trigger takes a bounded step from the current value, reflecting off 0 and 1. Organic wandering rather than jumps. Step Size sets how far a step can move."
        }
    }
}

/// Shape of the Random mode's draws.
public enum ValueDistribution: String, CaseIterable
{
    case uniform = "Uniform"
    case gaussian = "Gaussian"
    case triangular = "Triangular"
}

public class NumberGeneratorNode : StrategyNode
{
    override public class var name: String { "Number Generator" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Emits a new value in [0, 1] on each rising edge of Signal. Mode (in Settings) picks how the next value is generated: Random draws, a bounded Walk, or an even-spread low-discrepancy sequence." }

    override public class var strategyOptions: [any NodeStrategyOption] { NumberGeneratorMode.allCases }

    // Title leads with the active mode (StrategyNode default), e.g. "Walk Number Generator".

    // Settings pane: the strategy picker plus usage guidance for the selected mode.
    override public var settingsSize: SettingsViewSize { .Small }

    override public func settingsView() -> AnyView
    {
        AnyView(StrategyGuidanceView(model: strategySettingsModel) { NumberGeneratorMode(rawValue: $0)?.usageGuidance ?? "" })
    }

    private static let goldenRatioConjugate: Float = 0.6180339887498949

    private static let allDynamicNames: Set<String> = [
        "inputSignal", "inputMinChange", "inputDistribution", "inputStepSize", "outputValue",
    ]

    private var value: Float = 0
    private var spreadPhase: Float = 0 // raw low-discrepancy phase for Even Spread
    private var previousSignal: Bool? = nil
    private var hasEmitted: Bool = false

    override public func rebuildPorts(forStrategy strategy: String)
    {
        let mode = NumberGeneratorMode(rawValue: strategy) ?? .random

        var wanted: [(name: String, port: Port)] =
        [
            ("inputSignal", ParameterPort(parameter: BoolParameter("Signal", false, .button, "Rising edge (false → true) generates a new value"))),
        ]

        switch mode
        {
        case .random:
            wanted.append(("inputMinChange", ParameterPort(parameter: FloatParameter("Minimum Change", 0.3, 0.0, 1.0, .inputfield, "Smallest allowed difference between the previous output and the new value"))))
            wanted.append(("inputDistribution", ParameterPort(parameter: StringParameter("Distribution", ValueDistribution.uniform.rawValue, ValueDistribution.allCases.map(\.rawValue), .dropdown, "Shape of the random draw"))))
        case .walk:
            wanted.append(("inputStepSize", ParameterPort(parameter: FloatParameter("Step Size", 0.1, 0.0, 1.0, .inputfield, "Largest step taken from the current value on each trigger"))))
        case .evenSpread:
            wanted.append(("inputDistribution", ParameterPort(parameter: StringParameter("Distribution", ValueDistribution.uniform.rawValue, ValueDistribution.allCases.map(\.rawValue), .dropdown, "Shape the evenly-spread values follow"))))
        }

        wanted.append(("outputValue", NodePort<Float>(name: "Number", kind: .Outlet, description: "The current value in [0, 1]")))

        let wantedNames = Set(wanted.map(\.name))
        for name in Self.allDynamicNames.subtracting(wantedNames)
        {
            if let p = findPort(named: name) { removePort(p) }
        }
        for (name, p) in wanted where findPort(named: name) == nil
        {
            addDynamicPort(p, name: name)
        }

        self.resetGeneratorState()
    }

    override public func startExecution(renderer: GraphRenderer) throws
    {
        self.resetGeneratorState()
    }

    private func resetGeneratorState()
    {
        self.previousSignal = nil
        self.hasEmitted = false
        switch self.strategyOption(as: NumberGeneratorMode.self) ?? .random
        {
        case .random:
            self.value = Float.random(in: 0 ..< 1) // seed a representative value, like Walk / Even Spread
        case .walk:
            self.value = 0.5
        case .evenSpread:
            self.spreadPhase = Float.random(in: 0 ..< 1) // random starting phase per instance
            self.value = Self.quantile(self.spreadPhase, self.distributionValue())
        }
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputSignal: ParameterPort<Bool> = findPort(named: "inputSignal"),
              let outputValue: NodePort<Float> = findPort(named: "outputValue")
        else { return }

        let mode = self.strategyOption(as: NumberGeneratorMode.self) ?? .random
        let signal = inputSignal.value ?? false

        // Rising edge: previous false, current true. First execute has no
        // previous, so nothing fires on the initial frame even if Signal is
        // already true — caller must drive a transition.
        let triggered: Bool
        if let prev = self.previousSignal { triggered = signal && !prev } else { triggered = false }
        self.previousSignal = signal

        if triggered
        {
            switch mode
            {
            case .random:
                self.value = self.drawRandom()
            case .walk:
                self.value = self.walkStep(from: self.value)
            case .evenSpread:
                self.spreadPhase = (self.spreadPhase + Self.goldenRatioConjugate).truncatingRemainder(dividingBy: 1)
                self.value = Self.quantile(self.spreadPhase, self.distributionValue())
            }
        }

        if !self.hasEmitted || triggered
        {
            self.hasEmitted = true
            outputValue.send(self.value)
        }
    }

    private func drawRandom() -> Float
    {
        let minChange: Float = (findPort(named: "inputMinChange") as ParameterPort<Float>?)?.value ?? 0
        let distribution = self.distributionValue()

        // Uniform has an exact windowed draw. Shaped distributions reject draws
        // inside the minimum-change window (capped so it always terminates).
        if distribution == .uniform
        {
            return Self.uniformBeyond(value: self.value, delta: minChange)
        }

        var candidate = Self.quantile(Float.random(in: 0 ..< 1), distribution)
        var attempts = 0
        while abs(candidate - self.value) < minChange && attempts < 16
        {
            candidate = Self.quantile(Float.random(in: 0 ..< 1), distribution)
            attempts += 1
        }

        // A peaked distribution can put almost all its mass inside the window when
        // the current value sits near the peak and Minimum Change is wide, so
        // rejection sampling may never land a valid draw. Minimum Change is a hard
        // contract, so when the shaped draw can't honour it, fall back to the exact
        // windowed uniform draw — trading distribution shape (only on these frames)
        // for the guaranteed separation the user asked for.
        if abs(candidate - self.value) < minChange
        {
            return Self.uniformBeyond(value: self.value, delta: minChange)
        }
        return candidate
    }

    private func distributionValue() -> ValueDistribution
    {
        ValueDistribution(rawValue: (findPort(named: "inputDistribution") as ParameterPort<String>?)?.value ?? "") ?? .uniform
    }

    private func walkStep(from value: Float) -> Float
    {
        let stepSize = max(0, (findPort(named: "inputStepSize") as ParameterPort<Float>?)?.value ?? 0)
        var next = value + Float.random(in: -stepSize ... stepSize)
        if next < 0 { next = -next }       // reflect off the lower bound
        if next > 1 { next = 2 - next }    // reflect off the upper bound
        return min(1, max(0, next))
    }

    /// Inverse CDF (quantile): maps a uniform value in [0, 1] to the shaped
    /// distribution. Applied to a low-discrepancy sequence it preserves the even
    /// spread while reshaping it; applied to uniform randomness it draws a shaped
    /// random sample.
    private static func quantile(_ u: Float, _ distribution: ValueDistribution) -> Float
    {
        switch distribution
        {
        case .uniform:
            return min(1, max(0, u))
        case .triangular:
            let p = min(1, max(0, u))
            return p < 0.5 ? sqrt(p * 0.5) : 1 - sqrt((1 - p) * 0.5)
        case .gaussian:
            let p = min(1 - 1e-6, max(1e-6, Double(u)))
            let z = Self.inverseStandardNormal(p)
            return min(1, max(0, Float(0.5 + z * 0.15)))
        }
    }

    // Acklam coefficients, hoisted to type scope so they are not heap-allocated
    // on every call (inverseStandardNormal runs on the per-trigger draw path).
    // a / b shape the central region's rational approximation, c / d the tails.
    private static let acklamCentralNumerator = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
    private static let acklamCentralDenominator = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01, -1.328068155288572e+01]
    private static let acklamTailNumerator = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
    private static let acklamTailDenominator = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00]

    /// Acklam's rational approximation of the standard-normal inverse CDF.
    private static func inverseStandardNormal(_ p: Double) -> Double
    {
        // Local aliases keep Horner's-method evaluation legible; binding to the
        // shared static arrays copies only the reference (no allocation).
        let a = Self.acklamCentralNumerator
        let b = Self.acklamCentralDenominator
        let c = Self.acklamTailNumerator
        let d = Self.acklamTailDenominator
        let pLow = 0.02425
        let pHigh = 1 - pLow

        if p < pLow
        {
            let q = sqrt(-2 * log(p))
            return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                   ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        else if p <= pHigh
        {
            let q = p - 0.5
            let r = q * q
            return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q /
                   (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
        }
        else
        {
            let q = sqrt(-2 * log(1 - p))
            return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                    ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
    }

    /// Uniform sample from [0, 1] with a window of +/- delta around `value`
    /// excluded. Degenerate cases (the excluded window covers the whole
    /// interval) fall back to the upper end.
    private static func uniformBeyond(value: Float, delta: Float) -> Float
    {
        let clampedValue = max(0, min(1, value))
        let clampedDelta = max(0, min(1, delta))
        let range = min(clampedValue + clampedDelta, 1) - max(clampedValue - clampedDelta, 0)
        let space = 1 - range
        let rand: Float = space > 0 ? Float.random(in: 0 ..< 1) * space : 0
        return rand < clampedValue - clampedDelta ? rand : rand + range
    }
}
