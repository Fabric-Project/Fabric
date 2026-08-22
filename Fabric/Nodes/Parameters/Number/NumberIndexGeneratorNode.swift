//
//  NumberIndexGeneratorNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal
import SwiftUI

/// How the Index Generator chooses the next index on each trigger. Modes are a
/// semantic choice that does not reshape ports, so — like the Number Generator —
/// this lives on the Settings picker (a StrategyNode strategy) rather than a wired port.
public enum IndexGeneratorMode: String, NodeStrategyOption, CaseIterable
{
    /// Uniform random over [0, Size); immediate repeats allowed.
    case random = "Random"
    /// Uniform random, never the same index twice in a row.
    case randomNoImmediateRepeat = "Random, no immediate repeat"
    /// A shuffled permutation dealt out one at a time; every index appears
    /// once before any repeats, with no repeat across the reshuffle seam.
    case shuffle = "Shuffle"
    /// 0, 1, 2, … in order.
    case sequential = "Sequential"

    /// True for modes with a natural end (one full pass through every index),
    /// where the Loop toggle chooses between restarting and holding.
    public var isFinite: Bool {
        switch self {
        case .shuffle, .sequential: return true
        case .random, .randomNoImmediateRepeat: return false
        }
    }

    /// One or two sentences shown in the Settings pane to explain the mode.
    public var usageGuidance: String
    {
        switch self
        {
        case .random:
            return "Each signal draws a fresh index uniformly at random over [0, Size). Draws are independent, so the same index can come up twice in a row."
        case .randomNoImmediateRepeat:
            return "Uniform random like Random, but the new index is never the same as the last one — so it always visibly changes, without settling into a fixed order."
        case .shuffle:
            return "Deals out a shuffled run of every index once before any repeats, reshuffling with no repeat across the seam. Loop restarts each pass; off holds the final index."
        case .sequential:
            return "Steps 0, 1, 2, … in order. Loop wraps back to 0 at the end; off holds the last index."
        }
    }
}

public class NumberIndexGeneratorNode : StrategyNode
{
    override public class var name: String { "Index Generator" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Emits an index in [0, Size) on each signal. Mode (in Settings): Random, no immediate repeat, Shuffle, or Sequential. For the finite modes, Loop restarts the sequence or holds the last index." }

    override public class var strategyOptions: [any NodeStrategyOption] { IndexGeneratorMode.allCases }

    // Title leads with the active mode (StrategyNode default), e.g. "Shuffle Index Generator".

    // Preserve the original default of Shuffle (strategyOptions leads with Random).
    override public class var defaultStrategy: String { IndexGeneratorMode.shuffle.rawValue }

    // Settings pane: the strategy picker plus usage guidance for the selected mode.
    override public var settingsSize: SettingsViewSize { .Small }

    override public func settingsView() -> AnyView
    {
        AnyView(StrategyGuidanceView(model: strategySettingsModel) { IndexGeneratorMode(rawValue: $0)?.usageGuidance ?? "" })
    }

    // Every mode carries Signal, Size, and Index; only the finite modes add Loop.
    private static let allDynamicNames: Set<String> = ["inputSignal", "inputSize", "inputLoop", "outputIndex"]

    private var index: Int = 0
    private var previousSignal: Bool? = nil
    private var hasEmitted: Bool = false

    // Sequence state, reset whenever Size, Mode, or Loop changes.
    private var bag: [Int] = []        // remaining draws for Shuffle
    private var finished: Bool = false // finite sequence done, Loop off → hold

    override public func rebuildPorts(forStrategy strategy: String)
    {
        let mode = IndexGeneratorMode(rawValue: strategy) ?? .shuffle

        var wanted: [(name: String, port: Port)] =
        [
            ("inputSignal", ParameterPort(parameter: BoolParameter("Signal", false, .button, "A signal advances to the next index"))),
            ("inputSize", ParameterPort(parameter: IntParameter("Size", 4, 1, 1_000_000, .inputfield, "Index count; output in [0, Size)"))),
        ]

        // Loop only bites on the finite sequences (Shuffle / Sequential), where it
        // chooses restart-vs-hold once every index has appeared. Random modes never
        // finish, so the toggle would be inert — omit it entirely.
        if mode.isFinite {
            wanted.append(("inputLoop", ParameterPort(parameter: BoolParameter("Loop", true, .toggle, "At the end of a finite sequence, restart it or hold the last index"))))
        }

        wanted.append(("outputIndex", NodePort<Int>(name: "Index", kind: .Outlet, description: "Current index in [0, Size)")))

        let wantedNames = Set(wanted.map(\.name))
        for name in Self.allDynamicNames.subtracting(wantedNames)
        {
            if let p = findPort(named: name) { removePort(p) }
        }
        for (name, p) in wanted where findPort(named: name) == nil
        {
            addDynamicPort(p, name: name)
        }

        self.resetSequence()
    }

    public var inputSignal: ParameterPort<Bool> { port(named: "inputSignal") }
    public var inputSize: ParameterPort<Int> { port(named: "inputSize") }
    public var inputLoop: ParameterPort<Bool>? { findPort(named: "inputLoop") }
    public var outputIndex: NodePort<Int> { port(named: "outputIndex") }

    override public func startExecution(renderer: GraphRenderer) throws {
        self.index = 0
        self.previousSignal = nil
        self.hasEmitted = false
        self.resetSequence()
    }

    private func resetSequence() {
        self.bag = []
        self.finished = false
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        // Mode lives on the Settings strategy now, not a port; switching it rebuilds
        // ports and resets the sequence via rebuildPorts, so it needs no change-check here.
        let loopPort: ParameterPort<Bool>? = self.inputLoop
        let anyChanged = self.inputSignal.valueDidChange
            || self.inputSize.valueDidChange
            || (loopPort?.valueDidChange ?? false)
        guard anyChanged || !self.hasEmitted else { return }

        let size = max(1, self.inputSize.value ?? 1)
        let mode = self.strategyOption(as: IndexGeneratorMode.self) ?? .shuffle
        let loop = loopPort?.value ?? true

        // Changing Size or Loop restarts the sequence and re-clamps the held index
        // into the new range.
        let indexBeforeClamp = self.index
        if self.inputSize.valueDidChange || (loopPort?.valueDidChange ?? false) {
            self.resetSequence()
            self.index = min(self.index, size - 1)
        }
        let indexReclamped = self.index != indexBeforeClamp

        let signal = self.inputSignal.value ?? false

        // Rising edge: previous false, current true. First execute has no
        // previous, so nothing advances on the initial frame.
        let triggered: Bool
        if let prev = self.previousSignal {
            triggered = signal && !prev
        } else {
            triggered = false
        }
        self.previousSignal = signal

        if triggered {
            self.advance(size: size, mode: mode, loop: loop)
        }

        // Re-emit when a Size change re-clamped the held index: otherwise the
        // output keeps publishing an index that is now out of range for the
        // shrunk Size, driving downstream lookups out of bounds until the next
        // trigger.
        if !self.hasEmitted || triggered || indexReclamped {
            self.hasEmitted = true
            self.outputIndex.send(self.index)
        }
    }

    private func advance(size: Int, mode: IndexGeneratorMode, loop: Bool) {
        if mode.isFinite && self.finished { return }

        switch mode {
        case .random:
            self.index = Int.random(in: 0 ..< size)

        case .randomNoImmediateRepeat:
            if size <= 1 {
                self.index = 0
            } else {
                var draw = Int.random(in: 0 ..< (size - 1))
                if draw >= self.index { draw += 1 } // skip the current index
                self.index = draw
            }

        case .sequential:
            // Step to the next index. The resting/seed value already shows the
            // current index, so a trigger advances past it rather than repeating
            // it (matching Shuffle / no-immediate-repeat, which never re-emit the
            // seed). The loop seam back to 0 is a genuine change and is allowed.
            let next = self.index + 1
            if next >= size {
                if loop { self.index = 0 } else { self.finished = true }
            } else {
                self.index = next
            }

        case .shuffle:
            if self.bag.isEmpty {
                self.refillBag(size: size)
            }
            self.index = self.bag.removeLast()
            if self.bag.isEmpty && !loop {
                self.finished = true
            }
        }
    }

    /// Build a fresh shuffled bag of 0..<size. The next draw is `bag.removeLast()`;
    /// if that would repeat the last-emitted index, swap it out so the
    /// reshuffle seam never repeats.
    private func refillBag(size: Int) {
        var next = Array(0 ..< size).shuffled()
        if self.hasEmitted, size > 1, next.last == self.index {
            next.swapAt(next.count - 1, 0)
        }
        self.bag = next
    }
}
