//
//  NumberPulseNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class NumberPulseNode : Node
{
    override public class var name: String { "Pulse" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Emits a signal once every Period seconds. Phase staggers where in the cycle it fires, so Pulses sharing a Period fire out of step." }

    // Accumulated phase in [0, 1). Advanced each frame by deltaTime / period so
    // live Period changes stay continuous (unlike time / period, which jumps).
    // A pulse fires on the frame where phase (plus Phase offset) crosses a cycle
    // boundary.
    private var phase: Float = 0

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPeriod", ParameterPort(parameter: FloatParameter("Period (secs)", 1.0, 0.0, 60.0, .inputfield, "Seconds between signals; zero or below holds off."))),
            ("inputPhase", ParameterPort(parameter: FloatParameter("Phase", 0.0, 0.0, 1.0, .inputfield, "Offset (0–1) staggering where in the cycle it fires"))),
            ("outputSignal", NodePort<Bool>(name: "Signal", kind: .Outlet, description: "Signal, once per Period")),
        ]
    }

    public var inputPeriod: ParameterPort<Float> { port(named: "inputPeriod") }
    public var inputPhase: ParameterPort<Float> { port(named: "inputPhase") }
    public var outputSignal: NodePort<Bool> { port(named: "outputSignal") }

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
        let offset = self.inputPhase.value ?? 0

        // A non-positive period holds the pulse off.
        var fired = false
        if period > 0 {
            let increment = Float(executionInfo.timing.deltaTime) / period
            let before = self.phase + offset
            self.phase += increment
            // Firing on a crossing of the integer cycle boundary catches exactly
            // one pulse per period; multiple crossings in a single frame (period
            // shorter than the frame interval) collapse to one.
            fired = floor(self.phase + offset) > floor(before)
            self.phase -= floor(self.phase)
        }

        self.outputSignal.send(fired)
    }
}
