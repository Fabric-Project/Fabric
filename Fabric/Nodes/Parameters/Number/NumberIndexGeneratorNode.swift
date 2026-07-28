//
//  NumberIndexGeneratorNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// How the Index Generator chooses the next index on each trigger.
public enum IndexGeneratorMode: String, CaseIterable
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
}

public class NumberIndexGeneratorNode : Node
{
    override public class var name: String { "Index Generator" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Emits an integer index in [0, Size) on each rising edge of Signal. Mode picks how the next index is drawn (Random, no immediate repeat, Shuffle, or Sequential); Loop restarts finite sequences or holds the last index." }

    private var index: Int = 0
    private var previousSignal: Bool? = nil
    private var hasEmitted: Bool = false

    // Sequence state, reset whenever Size, Mode, or Loop changes.
    private var bag: [Int] = []        // remaining draws for Shuffle
    private var finished: Bool = false // finite sequence done, Loop off → hold

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputSignal", ParameterPort(parameter: BoolParameter("Signal", false, .button, "Rising edge (false → true) advances to the next index"))),
            ("inputSize", ParameterPort(parameter: IntParameter("Size", 4, 1, 1_000_000, .inputfield, "Number of indices; output is in [0, Size)"))),
            ("inputMode", ParameterPort(parameter: StringParameter("Mode", IndexGeneratorMode.shuffle.rawValue, IndexGeneratorMode.allCases.map(\.rawValue), .dropdown, "How the next index is chosen"))),
            ("inputLoop", ParameterPort(parameter: BoolParameter("Loop", true, .toggle, "When a finite sequence (Shuffle / Sequential) completes, restart it; otherwise hold the last index"))),
            ("outputIndex", NodePort<Int>(name: "Index", kind: .Outlet, description: "Current index in [0, Size)")),
        ]
    }

    public var inputSignal: ParameterPort<Bool> { port(named: "inputSignal") }
    public var inputSize: ParameterPort<Int> { port(named: "inputSize") }
    public var inputMode: ParameterPort<String> { port(named: "inputMode") }
    public var inputLoop: ParameterPort<Bool> { port(named: "inputLoop") }
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
        let anyChanged = self.inputSignal.valueDidChange
            || self.inputSize.valueDidChange
            || self.inputMode.valueDidChange
            || self.inputLoop.valueDidChange
        guard anyChanged || !self.hasEmitted else { return }

        let size = max(1, self.inputSize.value ?? 1)
        let mode = IndexGeneratorMode(rawValue: self.inputMode.value ?? "") ?? .shuffle
        let loop = self.inputLoop.value ?? true

        // Changing Size, Mode, or Loop restarts the sequence and re-clamps the
        // held index into the new range.
        let indexBeforeClamp = self.index
        if self.inputSize.valueDidChange || self.inputMode.valueDidChange || self.inputLoop.valueDidChange {
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
