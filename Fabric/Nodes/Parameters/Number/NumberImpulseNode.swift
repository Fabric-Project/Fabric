//
//  NumberImpulseNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class NumberImpulseNode : Node
{
    override public class var name: String { "Impulse" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Outputs 1 for `Duration` seconds on each rising edge of Signal (false → true), then returns to 0." }

    // Tick every frame so the timed-off transition fires even when no inputs
    // change — same pattern as NumberTriggerNode.
    public override var isDirty: Bool { get { true } set { } }

    private var state: Float = 0
    private var pulseEndTime: TimeInterval = 0
    private var previousSignal: Bool? = nil
    private var hasEmitted: Bool = false

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputSignal", ParameterPort(parameter: BoolParameter("Signal", false, .button, "Rising edge (false → true) starts a new pulse"))),
            ("inputDuration", ParameterPort(parameter: FloatParameter("Duration (secs)", 0.5, 0.0, 60.0, .inputfield, "Length of the high pulse in seconds"))),
            ("outputValue", NodePort<Float>(name: "Value", kind: .Outlet, description: "1 while pulse is active, 0 otherwise")),
        ]
    }

    public var inputSignal: ParameterPort<Bool> { port(named: "inputSignal") }
    public var inputDuration: ParameterPort<Float> { port(named: "inputDuration") }
    public var outputValue: NodePort<Float> { port(named: "outputValue") }

    override public func startExecution(context: GraphExecutionContext) {
        self.state = 0
        self.pulseEndTime = 0
        self.previousSignal = nil
        self.hasEmitted = false
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let now = context.timing.time
        let signal = self.inputSignal.value ?? false

        // Detect rising edge (false → true). First execute has no previous,
        // so nothing fires on the initial frame even if Signal is already
        // true — caller must drive a transition.
        let triggered: Bool
        if let prev = self.previousSignal {
            triggered = signal && !prev
        } else {
            triggered = false
        }
        self.previousSignal = signal

        var newState = self.state
        if triggered {
            let duration = TimeInterval(self.inputDuration.value ?? 0.5)
            self.pulseEndTime = now + max(0, duration)
            newState = 1
        } else if self.state == 1 && now >= self.pulseEndTime {
            newState = 0
        }

        if newState != self.state || !self.hasEmitted {
            self.state = newState
            self.hasEmitted = true
            self.outputValue.send(self.state)
        }
    }
}
