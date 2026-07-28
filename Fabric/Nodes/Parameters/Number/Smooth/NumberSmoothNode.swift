//
//  NumberSmoothNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal
import SwiftUI

/// Smoothing algorithm, chosen in the node's Settings. Different modes expose
/// different parameter ports, so this lives on the Settings picker (a
/// StrategyNode strategy) rather than a wired port.
public enum SmoothFilterMode: String, NodeStrategyOption, CaseIterable
{
    /// 1€ (One Euro) adaptive low-pass; its cutoff rises with input speed to
    /// cut lag during fast motion.
    case oneEuro = "One Euro"
    /// A one-pole exponential filter — a single decay time constant.
    case exponential = "Exponential"
    /// A constant-rate glide that reaches the target along a straight ramp.
    case slew = "Slew"
    /// A damped second-order follower with momentum; Damping ranges from bouncy
    /// (overshoot) through critically damped to overdamped (sluggish).
    case spring = "Spring"

    /// One or two sentences shown in the Settings pane to explain when to reach
    /// for this mode.
    public var usageGuidance: String
    {
        switch self
        {
        case .oneEuro:
            return "Adaptive low-pass that eases the value and automatically loosens during fast motion to stay responsive. A strong default for live, jittery inputs. Responsiveness sets how much fast motion cuts lag."
        case .exponential:
            return "A simple one-pole filter: a single, steady ease toward the input. Predictable and cheap. Pair with Direction — Down gives a classic VU-meter fall."
        case .slew:
            return "Glides to the target at a constant speed, arriving along a straight ramp rather than easing in. Good for steady mechanical motion and hard-capped fall rates."
        case .spring:
            return "Follows with momentum. Low Damping overshoots and bounces (elastic); the middle is a smooth critically-damped arrival; high Damping is slow and heavy."
        }
    }
}

/// Which direction of motion is smoothed. The un-smoothed direction tracks the
/// input instantly.
public enum SmoothDirection: String, CaseIterable
{
    /// Smooth both directions (symmetric low-pass).
    case upDown = "Up & Down"
    /// Smooth rises; fall instantly.
    case up = "Up"
    /// Smooth falls; rise instantly (VU-meter peak-with-decay).
    case down = "Down"
}

public class NumberSmoothNode : StrategyNode
{
    override public class var name: String { "Smooth" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Smooths a number over time. Filter Mode picks the algorithm (One Euro, Exponential, Slew, or Spring); Direction limits smoothing to rises, falls, or both." }

    override public class var strategyOptions: [any NodeStrategyOption] { SmoothFilterMode.allCases }

    // Settings pane: the strategy picker plus usage guidance for the selected mode.
    override public var settingsSize: SettingsViewSize { .Small }

    override public func settingsView() -> AnyView
    {
        AnyView(StrategyGuidanceView(model: strategySettingsModel) { SmoothFilterMode(rawValue: $0)?.usageGuidance ?? "" })
    }

    // Smoothing amount [0,1] maps geometrically to an exponential time constant,
    // keeping the whole knob usable — barely perceptible near 0, very slow near 1.
    private static let expMinTau: Double = 0.005 // seconds — barely perceptible
    private static let expMaxTau: Double = 10.0  // seconds — very slow

    // Smoothing amount [0,1] maps geometrically to the One Euro base cutoff (Hz):
    // a high cutoff barely smooths, a low cutoff smooths heavily.
    private static let euroMaxCutoff: Double = 30.0 // Hz — barely perceptible
    private static let euroMinCutoff: Double = 0.1  // Hz — very smooth
    private static let euroMaxBeta: Double = 1.0    // Responsiveness = 1 maps here

    // Slew: Smoothing maps geometrically to the seconds taken to glide one unit
    // of distance; the rate is constant so larger moves take proportionally longer.
    private static let slewMinTime: Double = 0.005 // seconds per unit — near-instant
    private static let slewMaxTime: Double = 10.0  // seconds per unit — very slow

    // Spring: Smoothing maps geometrically to the natural response time, Damping
    // linearly to the damping ratio (below 1 overshoots, 1 is critical, above is
    // overdamped).
    private static let springMinTime: Double = 0.02 // seconds — stiff/fast
    private static let springMaxTime: Double = 5.0  // seconds — slow/loose
    private static let springMinDamping: Double = 0.1 // very bouncy
    private static let springMaxDamping: Double = 2.0 // overdamped
    // Cap the integration substep so semi-implicit Euler stays stable when the
    // spring is stiff relative to the frame interval.
    private static let springMaxStepAngle: Double = 0.25
    private static let springMaxSubsteps: Int = 64

    private static let allDynamicNames: Set<String> = [
        "inputNumber", "inputSmoothing", "inputResponsiveness", "inputDamping", "inputDirection", "outputNumber",
    ]

    private let oneEuroFilter = OneEuroFilter(freq: 120.0)
    private var heldValue: Float = 0
    private var velocity: Float = 0
    private var hasValue: Bool = false

    override public func rebuildPorts(forStrategy strategy: String)
    {
        let mode = SmoothFilterMode(rawValue: strategy) ?? .oneEuro

        var wanted: [(name: String, port: Port)] =
        [
            ("inputNumber", ParameterPort(parameter: FloatParameter("Number", 0, .inputfield, "Value to smooth"))),
            ("inputSmoothing", ParameterPort(parameter: FloatParameter("Smoothing", 0.5, 0.0, 1.0, .inputfield, "Smoothing amount: 0 barely smooths, 1 smooths heavily"))),
        ]

        if mode == .oneEuro
        {
            wanted.append(("inputResponsiveness", ParameterPort(parameter: FloatParameter("Responsiveness", 0.0, 0.0, 1.0, .inputfield, "How much fast motion reduces lag (One Euro beta); 0 is a plain low-pass"))))
        }

        if mode == .spring
        {
            wanted.append(("inputDamping", ParameterPort(parameter: FloatParameter("Damping", 0.5, 0.0, 1.0, .inputfield, "0 is bouncy (overshoots), ~0.5 is critically damped, 1 is overdamped (sluggish)"))))
        }

        wanted.append(("inputDirection", ParameterPort(parameter: StringParameter("Direction", SmoothDirection.upDown.rawValue, SmoothDirection.allCases.map(\.rawValue), .dropdown, "Which direction is smoothed; the other tracks instantly. Down is VU-meter style."))))
        wanted.append(("outputNumber", NodePort<Float>(name: "Number", kind: .Outlet, description: "Smoothed value")))

        let wantedNames = Set(wanted.map(\.name))
        for name in Self.allDynamicNames.subtracting(wantedNames)
        {
            if let p = findPort(named: name) { removePort(p) }
        }
        for (name, p) in wanted where findPort(named: name) == nil
        {
            addDynamicPort(p, name: name)
        }

        self.resetSmoothingState()
    }

    override public func startExecution(renderer: GraphRenderer) throws
    {
        self.resetSmoothingState()
    }

    private func resetSmoothingState()
    {
        self.hasValue = false
        self.heldValue = 0
        self.velocity = 0
        self.oneEuroFilter.reset(to: 0)
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputNumber: ParameterPort<Float> = findPort(named: "inputNumber"),
              let outputNumber: NodePort<Float> = findPort(named: "outputNumber"),
              let input = inputNumber.value
        else { return }

        let mode = self.strategyOption(as: SmoothFilterMode.self) ?? .oneEuro

        // Seed on the first value so the output starts on the input rather than
        // smoothing up from zero.
        if !self.hasValue
        {
            self.heldValue = input
            self.velocity = 0
            self.hasValue = true
            self.oneEuroFilter.reset(to: Double(input))
            outputNumber.send(self.heldValue)
            return
        }

        let direction = self.directionValue()
        let rising = input > self.heldValue
        let smoothThisDirection: Bool
        switch direction
        {
        case .upDown: smoothThisDirection = true
        case .up:     smoothThisDirection = rising
        case .down:   smoothThisDirection = !rising
        }

        if !smoothThisDirection || input == self.heldValue
        {
            // Instant in this direction: snap, and reset the active filter's
            // state (including any spring momentum) so smoothing re-engages from
            // here without a jump.
            self.heldValue = input
            self.velocity = 0
            if mode == .oneEuro { self.oneEuroFilter.reset(to: Double(input)) }
        }
        else
        {
            let smoothing = Double(min(1, max(0, self.smoothingValue())))
            let dt = executionInfo.timing.deltaTime
            switch mode
            {
            case .exponential:
                let tau = Self.expMinTau * pow(Self.expMaxTau / Self.expMinTau, smoothing)
                let alpha = Float(1.0 - exp(-dt / tau))
                self.heldValue += alpha * (input - self.heldValue)

            case .oneEuro:
                let cutoff = Self.euroMaxCutoff * pow(Self.euroMinCutoff / Self.euroMaxCutoff, smoothing)
                self.oneEuroFilter.setMinCutoff(cutoff)
                self.oneEuroFilter.beta = Double(min(1, max(0, self.responsivenessValue()))) * Self.euroMaxBeta
                self.heldValue = Float(self.oneEuroFilter.Filter(Double(input), timestamp: executionInfo.timing.systemTime))

            case .slew:
                let secondsPerUnit = Self.slewMinTime * pow(Self.slewMaxTime / Self.slewMinTime, smoothing)
                let step = Float(dt / secondsPerUnit)
                let gap = input - self.heldValue
                self.heldValue += abs(gap) <= step ? gap : (gap > 0 ? step : -step)

            case .spring:
                self.stepSpring(toward: input, smoothing: smoothing, deltaTime: dt)
            }
        }

        outputNumber.send(self.heldValue)
    }

    /// Advance a damped harmonic oscillator toward `target` by `deltaTime`,
    /// substepping so semi-implicit Euler stays stable when the spring is stiff.
    private func stepSpring(toward target: Float, smoothing: Double, deltaTime: Double)
    {
        let responseTime = Self.springMinTime * pow(Self.springMaxTime / Self.springMinTime, smoothing)
        let omega = 1.0 / responseTime
        let damping = min(1, max(0, self.dampingValue()))
        let zeta = Self.springMinDamping + Double(damping) * (Self.springMaxDamping - Self.springMinDamping)

        // The substep budget bounds how much real time can be integrated while
        // keeping the step angle at its stable target. A deltaTime larger than that
        // budget only arises from a frame hitch or resume-from-pause; integrating
        // the whole gap is physically meaningless (a spring settles in a handful of
        // time constants) and would force the step angle past target, so clamp it.
        // Within a normal frame this is a no-op.
        let maxIntegrationWindow = Double(Self.springMaxSubsteps) * Self.springMaxStepAngle / omega
        let integrationTime = min(deltaTime, maxIntegrationWindow)

        let substeps = max(1, min(Self.springMaxSubsteps, Int((omega * integrationTime / Self.springMaxStepAngle).rounded(.up))))
        let h = integrationTime / Double(substeps)

        var position = Double(self.heldValue)
        var velocity = Double(self.velocity)
        let goal = Double(target)
        for _ in 0 ..< substeps
        {
            let acceleration = omega * omega * (goal - position) - 2 * zeta * omega * velocity
            velocity += acceleration * h
            position += velocity * h
        }

        self.heldValue = Float(position)
        self.velocity = Float(velocity)
    }

    private func smoothingValue() -> Float
    {
        let port: ParameterPort<Float>? = findPort(named: "inputSmoothing")
        return port?.value ?? 0.5
    }

    private func responsivenessValue() -> Float
    {
        let port: ParameterPort<Float>? = findPort(named: "inputResponsiveness")
        return port?.value ?? 0
    }

    private func dampingValue() -> Float
    {
        let port: ParameterPort<Float>? = findPort(named: "inputDamping")
        return port?.value ?? 0.5
    }

    private func directionValue() -> SmoothDirection
    {
        let port: ParameterPort<String>? = findPort(named: "inputDirection")
        return SmoothDirection(rawValue: port?.value ?? "") ?? .upDown
    }
}

