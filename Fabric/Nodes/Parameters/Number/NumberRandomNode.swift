//
//  NumberRandomNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class NumberRandomNode : Node
{
    override public class var name: String { "Random Value" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Emits a new random value in [0, 1] on each rising edge of Signal (false → true). Minimum Change guarantees the new value differs from the previous output by at least that amount, by drawing from [0, 1] with a window of +/- Minimum Change around the current value excluded." }

    private var value: Float = 0
    private var previousSignal: Bool? = nil
    private var hasEmitted: Bool = false

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputSignal", ParameterPort(parameter: BoolParameter("Signal", false, .button, "Rising edge (false → true) fires a new random value"))),
            ("inputMinChange", ParameterPort(parameter: FloatParameter("Minimum Change", 0.3, 0.0, 1.0, .inputfield, "Smallest allowed difference between the previous output and the new random value"))),
            ("outputValue", NodePort<Float>(name: "Value", kind: .Outlet, description: "The current random value in [0, 1]")),
        ]
    }

    public var inputSignal: ParameterPort<Bool> { port(named: "inputSignal") }
    public var inputMinChange: ParameterPort<Float> { port(named: "inputMinChange") }
    public var outputValue: NodePort<Float> { port(named: "outputValue") }

    override public func startExecution(context: GraphExecutionContext) {
        self.value = 0
        self.previousSignal = nil
        self.hasEmitted = false
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let anyChanged = self.inputSignal.valueDidChange || self.inputMinChange.valueDidChange
        guard anyChanged || !self.hasEmitted else { return }

        let signal = self.inputSignal.value ?? false

        // Rising edge: previous false, current true. First execute has no
        // previous, so nothing fires on the initial frame even if Signal is
        // already true — caller must drive a transition.
        let triggered: Bool
        if let prev = self.previousSignal {
            triggered = signal && !prev
        } else {
            triggered = false
        }
        self.previousSignal = signal

        if triggered {
            let delta = self.inputMinChange.value ?? 0
            self.value = Self.randomBeyond(value: self.value, delta: delta)
        }

        if !self.hasEmitted || triggered {
            self.hasEmitted = true
            self.outputValue.send(self.value)
        }
    }

    /// Uniform sample from [0, 1] with a window of +/- delta around `value`
    /// excluded. Port of Volta's NormalisedRandomBeyondDelta; degenerate cases
    /// (excluded window covers the full interval) fall back to the upper end.
    private static func randomBeyond(value: Float, delta: Float) -> Float {
        let clampedValue = max(0, min(1, value))
        let clampedDelta = max(0, min(1, delta))
        let range = min(clampedValue + clampedDelta, 1) - max(clampedValue - clampedDelta, 0)
        let space = 1 - range
        let rand: Float = space > 0 ? Float.random(in: 0..<1) * space : 0
        return rand < clampedValue - clampedDelta ? rand : rand + range
    }
}
