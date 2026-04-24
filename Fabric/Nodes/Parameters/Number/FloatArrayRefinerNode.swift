//
//  FloatArrayRefinerNode.swift
//  Fabric
//

import Foundation
import SwiftUI
import Satin
import simd
import Metal

public class FloatArrayRefinerNode : Node
{
    public enum SelectionMode: String, CaseIterable
    {
        case ranked  = "Ranked"
        case manual  = "Manual"
    }

    public enum Partitioning: String, CaseIterable
    {
        case none   = "None"
        case zoned  = "Zoned"
    }

    override public class var name:String { "Float Array Refiner" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .Idle }
    override public class var nodeDescription: String { "Reduces a float array to the Count values whose ranking scores are largest, preserving input order. Supply a separate Scores array to rank by (e.g. Float Array Dynamics) — if unconnected, values are ranked by themselves. Mode: Ranked picks by score; Manual lets you click values in the settings popover. Partitioning optionally divides the input into Count equal zones and picks one per zone." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputNumbers", NodePort<ContiguousArray<Float>>(name: "Numbers", kind: .Inlet, description: "Array of values to reduce. The output is selected values from this array.")),
            ("inputScores", NodePort<ContiguousArray<Float>>(name: "Scores", kind: .Inlet, description: "Array of ranking scores, same length as Numbers. Feed dynamism scores (Float Array Dynamics) here to pick the most dynamic values. If unconnected, Numbers are ranked by themselves.")),
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 4, 1, 256, .inputfield, "Number of output values to keep"))),
            ("inputMode", ParameterPort(parameter: StringParameter("Mode", SelectionMode.ranked.rawValue, SelectionMode.allCases.map(\.rawValue), .dropdown, "Ranked: top-Count by score. Manual: click in the settings popover."))),
            ("inputPartitioning", ParameterPort(parameter: StringParameter("Partitioning", Partitioning.none.rawValue, Partitioning.allCases.map(\.rawValue), .dropdown, "None: pick values across the whole input. Zoned: divide into Count equal zones and pick one per zone."))),
            ("outputNumbers", NodePort<ContiguousArray<Float>>(name: "Numbers", kind: .Outlet, description: "Selected values from Numbers in original index order")),
        ]
    }

    public var inputNumbers:NodePort<ContiguousArray<Float>>     { port(named: "inputNumbers") }
    public var inputScores:NodePort<ContiguousArray<Float>>      { port(named: "inputScores") }
    public var inputCount:ParameterPort<Int>                     { port(named: "inputCount") }
    public var inputMode:ParameterPort<String>                   { port(named: "inputMode") }
    public var inputPartitioning:ParameterPort<String>           { port(named: "inputPartitioning") }
    public var outputNumbers:NodePort<ContiguousArray<Float>>    { port(named: "outputNumbers") }

    // Manual-mode selection, oldest→newest order so FIFO eviction trims
    // the front when `count` is exceeded. Persisted so manual picks survive
    // document save/load.
    public internal(set) var manualSelection: [Int] = []

    @ObservationIgnored private(set) var lastKnownBandCount: Int = 0

    // Visualization (consumed by the settings popover, updated only while open)
    @ObservationIgnored public var visualizationBands: [Float] = []
    @ObservationIgnored public var visualizationSelected: Set<Int> = []
    // Score ticks overlaid on the bars. Empty when the Scores input is not
    // connected (or mismatches length) — in that case ranking-by-value makes
    // the ticks redundant with the bars, so we hide them.
    @ObservationIgnored public var visualizationScores: [Float] = []

    // MARK: - Codable (persist manual selection)

    private enum FloatArrayRefinerCodingKeys: String, CodingKey
    {
        case manualSelection
    }

    public required init(context: Context)
    {
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        let container = try decoder.container(keyedBy: FloatArrayRefinerCodingKeys.self)
        self.manualSelection = (try container.decodeIfPresent([Int].self, forKey: .manualSelection)) ?? []
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: FloatArrayRefinerCodingKeys.self)
        try container.encode(self.manualSelection, forKey: .manualSelection)
    }

    // MARK: - Settings popover

    override public func providesSettingsView() -> Bool { true }
    override public func settingsView() -> AnyView { AnyView(FloatArrayRefinerNodeSettingsView(node: self)) }
    override public var settingsSize: SettingsViewSize { .Custom(size: CGSize(width: 460, height: 240)) }

    // MARK: - Execution

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: any MTLCommandBuffer)
    {
        guard let values = self.inputNumbers.value, !values.isEmpty else { return }
        let bandCount = values.count
        self.lastKnownBandCount = bandCount

        // Ranking scores: external Scores input if connected and length-
        // matched, otherwise rank the values by themselves.
        let scores: ContiguousArray<Float>
        let scoresAreExternal: Bool
        if let external = self.inputScores.value, external.count == bandCount
        {
            scores = external
            scoresAreExternal = true
        }
        else
        {
            scores = values
            scoresAreExternal = false
        }

        let mode = SelectionMode(rawValue: self.inputMode.value ?? SelectionMode.ranked.rawValue) ?? .ranked
        let partitioning = Partitioning(rawValue: self.inputPartitioning.value ?? Partitioning.none.rawValue) ?? .none

        let rawCount = self.inputCount.value ?? 4
        let count = max(1, min(bandCount, rawCount))

        let topIndices: [Int]
        switch (mode, partitioning)
        {
        case (.manual, .none):
            topIndices = self.resolvedManualIndices(count: count, bandCount: bandCount)

        case (.manual, .zoned):
            topIndices = self.resolvedManualZonedIndices(count: count, bandCount: bandCount)

        case (.ranked, .none):
            // Top-K by score across the whole array, tie-broken by lower
            // index for stability, then re-sorted ascending so input order
            // is preserved in the output.
            topIndices = (0..<bandCount)
                .sorted { lhs, rhs in
                    let a = scores[lhs]
                    let b = scores[rhs]
                    if a != b { return a > b }
                    return lhs < rhs
                }
                .prefix(count)
                .sorted()

        case (.ranked, .zoned):
            topIndices = self.topPerZoneByScore(scores: scores, count: count, bandCount: bandCount)
        }

        // Emit the Numbers at the chosen indices (not the scores — scores
        // only control which indices are chosen).
        var output = ContiguousArray<Float>()
        output.reserveCapacity(topIndices.count)
        for idx in topIndices
        {
            let v = values[idx]
            output.append(v.isFinite ? v : 0)
        }
        self.outputNumbers.send(output)

        if self.showSettings
        {
            // Normalize the visualization copy of values so bars are readable
            // regardless of absolute scale. Output is unnormalized.
            let maxAbsValues: Float = values.reduce(0) { max($0, abs($1)) }
            let valueScale: Float = maxAbsValues > 1e-9 ? 1.0 / maxAbsValues : 1.0
            self.visualizationBands = values.map { v in
                let n = v * valueScale
                return n.isFinite ? max(0, min(1, n)) : 0
            }
            self.visualizationSelected = Set(topIndices)

            // Only overlay score ticks when the Scores input is genuinely
            // separate from the values (otherwise the ticks would just
            // duplicate the bar tops).
            if scoresAreExternal
            {
                let maxScore: Float = scores.reduce(0) { max($0, abs($1)) }
                let scoreScale: Float = maxScore > 1e-9 ? 1.0 / maxScore : 1.0
                self.visualizationScores = scores.map { s in
                    let n = s * scoreScale
                    return n.isFinite ? max(0, min(1, n)) : 0
                }
            }
            else
            {
                self.visualizationScores = []
            }
        }
    }

    /// Pick the highest-scoring band within each of `count` contiguous zones.
    /// Tie-break by lower index for stability. Output is already ascending
    /// because zones are visited in order.
    private func topPerZoneByScore(scores: ContiguousArray<Float>, count: Int, bandCount: Int) -> [Int]
    {
        guard count > 0, bandCount > 0 else { return [] }

        var result: [Int] = []
        result.reserveCapacity(count)

        for z in 0..<count
        {
            let zoneStart = z * bandCount / count
            let zoneEnd   = (z + 1) * bandCount / count
            guard zoneEnd > zoneStart else { continue }

            var bestIdx = zoneStart
            var bestVal = scores[zoneStart]
            if zoneEnd > zoneStart + 1
            {
                for i in (zoneStart + 1)..<zoneEnd
                {
                    let v = scores[i]
                    if v > bestVal { bestVal = v; bestIdx = i }
                }
            }
            result.append(bestIdx)
        }
        return result
    }

    /// Manual + Zoned: each zone gets exactly one output band. If the user
    /// has a manual pick in a zone, use their newest pick there; otherwise
    /// default to the zone's center band. Always returns ascending-by-index.
    private func resolvedManualZonedIndices(count: Int, bandCount: Int) -> [Int]
    {
        guard count > 0, bandCount > 0 else { return [] }

        var result: [Int] = []
        result.reserveCapacity(count)

        for z in 0..<count
        {
            let zoneStart = z * bandCount / count
            let zoneEnd   = (z + 1) * bandCount / count
            guard zoneEnd > zoneStart else { continue }

            if let pick = self.manualSelection.reversed().first(where: { $0 >= zoneStart && $0 < zoneEnd })
            {
                result.append(pick)
            }
            else
            {
                result.append((zoneStart + zoneEnd - 1) / 2)
            }
        }
        return result
    }

    /// Manual + None: under-count → spread-fill uniform positions; over-count
    /// → take youngest `count` picks. Always returns ascending-by-index.
    private func resolvedManualIndices(count: Int, bandCount: Int) -> [Int]
    {
        let validManual = self.manualSelection.filter { $0 >= 0 && $0 < bandCount }

        if validManual.count >= count
        {
            return Array(validManual.suffix(count)).sorted()
        }

        var result = validManual
        var resultSet = Set(validManual)

        for i in 0..<count
        {
            let target = bandCount * i / max(1, count)
            if !resultSet.contains(target), result.count < count
            {
                result.append(target)
                resultSet.insert(target)
            }
        }

        var idx = 0
        while result.count < count && idx < bandCount
        {
            if !resultSet.contains(idx)
            {
                result.append(idx)
                resultSet.insert(idx)
            }
            idx += 1
        }

        return result.sorted()
    }

    /// Called by the settings popover when the user clicks a band.
    /// - Partitioning = None: toggle membership in the manual list. On add,
    ///   FIFO-evicts from the front if the list would exceed the current
    ///   `count`.
    /// - Partitioning = Zoned: replace the zone's pick with the clicked band
    ///   (one-per-zone invariant). Clicking the already-selected band in a
    ///   zone is a no-op.
    public func toggleManualSelection(at index: Int)
    {
        let mode = SelectionMode(rawValue: self.inputMode.value ?? SelectionMode.ranked.rawValue) ?? .ranked
        guard mode == .manual else { return }
        guard index >= 0, index < self.lastKnownBandCount else { return }

        let partitioning = Partitioning(rawValue: self.inputPartitioning.value ?? Partitioning.none.rawValue) ?? .none
        let rawCount = self.inputCount.value ?? 4
        let count = max(1, min(self.lastKnownBandCount, rawCount))

        switch partitioning
        {
        case .none:
            if let existing = self.manualSelection.firstIndex(of: index)
            {
                self.manualSelection.remove(at: existing)
                return
            }
            self.manualSelection.append(index)
            while self.manualSelection.count > count
            {
                self.manualSelection.removeFirst()
            }

        case .zoned:
            let bc = self.lastKnownBandCount
            let zone = index * count / bc
            let zoneStart = zone * bc / count
            let zoneEnd   = (zone + 1) * bc / count
            self.manualSelection.removeAll { $0 >= zoneStart && $0 < zoneEnd }
            self.manualSelection.append(index)
            while self.manualSelection.count > bc
            {
                self.manualSelection.removeFirst()
            }
        }
    }
}

// MARK: - Settings View

private struct FloatArrayRefinerNodeSettingsView: View
{
    @Bindable var node: FloatArrayRefinerNode

    var body: some View
    {
        BandsVisualizer(
            bands:    { node.visualizationBands },
            selected: { node.visualizationSelected },
            scores:   { node.visualizationScores },
            onTap:    { i in node.toggleManualSelection(at: i) }
        )
    }
}
