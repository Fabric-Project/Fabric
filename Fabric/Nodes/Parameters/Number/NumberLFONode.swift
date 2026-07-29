//
//  NumberLFONode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// Low-frequency oscillator waveforms. Each maps a phase in [0, 1) to a
/// unipolar output in [0, 1].
public enum LFOWaveform: String, CaseIterable
{
    case sine = "Sine"
    case triangle = "Triangle"
    case sawtoothUp = "Sawtooth Up"
    case sawtoothDown = "Sawtooth Down"
    case square = "Square"

    /// Sample the waveform at `phase`, assumed already wrapped to [0, 1).
    public func sample(at phase: Float) -> Float {
        switch self {
        case .sine:         return 0.5 + 0.5 * sin(2 * .pi * phase)
        case .triangle:     return 1 - abs(2 * phase - 1)
        case .sawtoothUp:   return phase
        case .sawtoothDown: return 1 - phase
        case .square:       return phase < 0.5 ? 1 : 0
        }
    }
}

public class NumberLFONode : Node
{
    override public class var name: String { "LFO" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Low-frequency oscillator. Outputs a value in [0, 1] that cycles through the selected Waveform once every Period seconds. Phase is accumulated per frame, so changing Period live shifts the rate without jumping the output. Phase offsets the position within the cycle, letting several LFOs run in sync but staggered." }

    // Accumulated phase in [0, 1). Advanced each frame by deltaTime / period so
    // live Period changes stay continuous (unlike time / period, which jumps).
    private var phase: Float = 0

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputWaveform", ParameterPort(parameter: StringParameter("Waveform", LFOWaveform.sine.rawValue, LFOWaveform.allCases.map(\.rawValue), .dropdown, "Oscillator waveform"))),
            ("inputPeriod", ParameterPort(parameter: FloatParameter("Period (secs)", 1.0, 0.0, 60.0, .inputfield, "Seconds per cycle. Zero or below freezes the oscillator."))),
            ("inputPhase", ParameterPort(parameter: FloatParameter("Phase", 0.0, 0.0, 1.0, .inputfield, "Phase offset (0–1) added to the cycle position"))),
            ("outputValue", NodePort<Float>(name: "Number", kind: .Outlet, description: "Current oscillator value in [0, 1]")),
        ]
    }

    public var inputWaveform: ParameterPort<String> { port(named: "inputWaveform") }
    public var inputPeriod: ParameterPort<Float> { port(named: "inputPeriod") }
    public var inputPhase: ParameterPort<Float> { port(named: "inputPhase") }
    public var outputValue: NodePort<Float> { port(named: "outputValue") }

    override public func startExecution(renderer: GraphRenderer) throws {
        self.phase = 0
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let period = self.inputPeriod.value ?? 1

        // Advance phase. A non-positive period holds the oscillator still.
        if period > 0 {
            let dt = Float(executionInfo.timing.deltaTime)
            self.phase += dt / period
            self.phase -= floor(self.phase)
        }

        let waveform = LFOWaveform(rawValue: self.inputWaveform.value ?? "") ?? .sine
        let offset = self.inputPhase.value ?? 0

        var p = self.phase + offset
        p -= floor(p)

        self.outputValue.send(waveform.sample(at: p))
    }
}
