//
//  FloatArrayDynamicsNode.swift
//  Fabric
//

import Foundation
import SwiftUI
import Satin
import simd
import Metal

public class FloatArrayDynamicsNode : Node
{
    public enum DynamismMetric: String, CaseIterable
    {
        case variance      = "Variance"
        case peakToTrough  = "Peak-to-Trough"
        case spectralFlux  = "Spectral Flux"
    }

    override public class var name:String { "Float Array Dynamics" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .Idle }
    override public class var nodeDescription: String { "Produces a per-index dynamism score for a float array over time. Variance balances slow and fast change; Peak-to-Trough tracks recent swing range; Spectral Flux rewards transients. Output length matches input. Chain into Float Array Refiner to pick the N most dynamic values. Pairs naturally with Audio Spectrum." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputNumbers", NodePort<ContiguousArray<Float>>(name: "Numbers", kind: .Inlet, description: "Array of float values to score (e.g. from Audio Spectrum)")),
            ("inputMode", ParameterPort(parameter: StringParameter("Mode", DynamismMetric.variance.rawValue, DynamismMetric.allCases.map(\.rawValue), .dropdown, "Scoring method: Variance (balanced), Peak-to-Trough (range of recent swings), Spectral Flux (rewards transients)"))),
            ("inputResponsiveness", ParameterPort(parameter: FloatParameter("Responsiveness", 0.5, 0.0, 1.0, .slider, "Metric reaction speed: 0 = long memory (stable), 1 = short memory (reactive)"))),
            ("outputScores", NodePort<ContiguousArray<Float>>(name: "Scores", kind: .Outlet, description: "Per-index dynamism score; length matches input. Raw (un-normalized) so downstream ranking is scale-independent. Feed into Float Array Refiner's Scores inlet.")),
        ]
    }

    public var inputNumbers:NodePort<ContiguousArray<Float>>     { port(named: "inputNumbers") }
    public var inputMode:ParameterPort<String>                   { port(named: "inputMode") }
    public var inputResponsiveness:ParameterPort<Float>          { port(named: "inputResponsiveness") }
    public var outputScores:NodePort<ContiguousArray<Float>>     { port(named: "outputScores") }

    // Per-index streaming state. All three metrics keep O(1) state per
    // index, so we allocate arrays for every metric and only touch the
    // active one per frame.
    @ObservationIgnored private var meanState: [Float]  = []   // Variance
    @ObservationIgnored private var varState: [Float]   = []   // Variance
    @ObservationIgnored private var maxState: [Float]   = []   // Peak-to-Trough
    @ObservationIgnored private var minState: [Float]   = []   // Peak-to-Trough
    @ObservationIgnored private var prevState: [Float]  = []   // Spectral Flux
    @ObservationIgnored private var fluxState: [Float]  = []   // Spectral Flux
    @ObservationIgnored private var dynamismScores: [Float] = []
    @ObservationIgnored private var lastKnownBandCount: Int = 0
    @ObservationIgnored private var lastKnownMode: DynamismMetric = .variance

    // Consumed by the settings popover; populated in execute() only while
    // showSettings is true. Scores are normalized to [0,1] for display only —
    // the actual output remains raw.
    @ObservationIgnored public var visualizationBands: [Float] = []

    override public func providesSettingsView() -> Bool { true }
    override public func settingsView() -> AnyView { AnyView(FloatArrayDynamicsNodeSettingsView(node: self)) }
    override public var settingsSize: SettingsViewSize { .Custom(size: CGSize(width: 460, height: 180)) }

    private func resetState(bandCount: Int, seedFrom values: ContiguousArray<Float>?)
    {
        meanState = Array(repeating: 0, count: bandCount)
        varState  = Array(repeating: 0, count: bandCount)
        maxState  = Array(repeating: 0, count: bandCount)
        minState  = Array(repeating: 0, count: bandCount)
        prevState = Array(repeating: 0, count: bandCount)
        fluxState = Array(repeating: 0, count: bandCount)
        dynamismScores = Array(repeating: 0, count: bandCount)

        // Seed the level-tracking states from current input so first-frame
        // transients don't dominate the score. Variance/flux self-converge.
        if let values, values.count == bandCount
        {
            for i in 0..<bandCount
            {
                let x = values[i].isFinite ? values[i] : 0
                meanState[i] = x
                maxState[i]  = x
                minState[i]  = x
                prevState[i] = x
            }
        }

        self.lastKnownBandCount = bandCount
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: any MTLCommandBuffer)
    {
        guard let values = self.inputNumbers.value, !values.isEmpty else { return }
        let bandCount = values.count

        let mode = DynamismMetric(rawValue: self.inputMode.value ?? DynamismMetric.variance.rawValue) ?? .variance
        if bandCount != self.lastKnownBandCount || mode != self.lastKnownMode
        {
            self.resetState(bandCount: bandCount, seedFrom: values)
            self.lastKnownMode = mode
        }

        let rawResp = self.inputResponsiveness.value ?? 0.5
        let responsiveness: Float = rawResp.isFinite ? max(0, min(1, rawResp)) : 0.5
        // Linear α in [0.02, 0.5]. At 60 fps that's a ~540 ms half-life at
        // slowest, ~1 frame at fastest.
        let alpha: Float = 0.02 + 0.48 * responsiveness

        self.updateScores(values: values, mode: mode, alpha: alpha, bandCount: bandCount)

        var output = ContiguousArray<Float>()
        output.reserveCapacity(bandCount)
        for s in dynamismScores
        {
            output.append(s.isFinite ? max(0, s) : 0)
        }
        self.outputScores.send(output)

        if self.showSettings
        {
            let maxScore: Float = output.reduce(0) { max($0, $1) }
            let scale: Float = maxScore > 1e-9 ? 1.0 / maxScore : 1.0
            self.visualizationBands = output.map { s in
                let n = s * scale
                return n.isFinite ? max(0, min(1, n)) : 0
            }
        }
    }

    private func updateScores(values: ContiguousArray<Float>,
                              mode: DynamismMetric,
                              alpha: Float,
                              bandCount: Int)
    {
        switch mode
        {
        case .variance:
            // EW mean + EW variance. Captures both slow swings and fast chatter.
            for i in 0..<bandCount
            {
                let raw = values[i]
                let x = raw.isFinite ? raw : 0
                meanState[i] += alpha * (x - meanState[i])
                let dev = x - meanState[i]
                varState[i] += alpha * (dev * dev - varState[i])
                let s = varState[i]
                dynamismScores[i] = s.isFinite ? s : 0
            }

        case .peakToTrough:
            // Fast-attack max/min followers, slow release — score is the
            // swing between recent high and recent low.
            let release: Float = alpha * 0.25
            for i in 0..<bandCount
            {
                let raw = values[i]
                let x = raw.isFinite ? raw : 0
                if x > maxState[i] { maxState[i] = x }
                else              { maxState[i] += release * (x - maxState[i]) }
                if x < minState[i] { minState[i] = x }
                else              { minState[i] += release * (x - minState[i]) }
                let s = maxState[i] - minState[i]
                dynamismScores[i] = s.isFinite ? max(0, s) : 0
            }

        case .spectralFlux:
            // EW of |Δx|. Rewards bands that change fast (transients,
            // percussive content).
            for i in 0..<bandCount
            {
                let raw = values[i]
                let x = raw.isFinite ? raw : 0
                let delta = abs(x - prevState[i])
                fluxState[i] += alpha * (delta - fluxState[i])
                prevState[i] = x
                let s = fluxState[i]
                dynamismScores[i] = s.isFinite ? s : 0
            }
        }
    }
}

// MARK: - Settings View

private struct FloatArrayDynamicsNodeSettingsView: View
{
    @Bindable var node: FloatArrayDynamicsNode

    var body: some View
    {
        BandsVisualizer(bands: { node.visualizationBands })
    }
}
