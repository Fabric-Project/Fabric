//
//  NumberTriggerNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class NumberTriggerNode : Node
{
    override public class var name: String { "Trigger" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Schmitt trigger with minimum on-duration. Output rises to 1 when Target crosses above Trigger Threshold. Output falls back to 0 once Target is below Release Threshold and at least Minimum Duration seconds have elapsed since the rising edge. Hysteresis (Trigger > Release) prevents chatter; Minimum Duration enforces a debounce floor." }

    // Tick every frame so the release condition is detected as time passes,
    // even when the input ports are static.
    public override var isDirty: Bool { get { true } set { } }

    private var state: Float = 0
    private var triggerTime: TimeInterval = 0
    private var hasEmitted: Bool = false

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputTarget", ParameterPort(parameter: FloatParameter("Target", 0.0, .inputfield, "Value being watched"))),
            ("inputTriggerThreshold", ParameterPort(parameter: FloatParameter("Trigger Threshold", 0.8, .inputfield, "Rising-edge threshold: Target at or above this value turns the output to 1"))),
            ("inputReleaseThreshold", ParameterPort(parameter: FloatParameter("Release Threshold", 0.5, .inputfield, "Falling-edge threshold: Target below this value (once Minimum Duration has elapsed) returns the output to 0"))),
            ("inputMinDurationSecs", ParameterPort(parameter: FloatParameter("Minimum Duration (secs)", 0.0, 0.0, 60.0, .inputfield, "Minimum seconds the output must remain 1 before it can fall back to 0"))),
            ("outputValue", NodePort<Float>(name: "Value", kind: .Outlet, description: "1 while latched high, 0 while latched low")),
        ]
    }

    public var inputTarget: ParameterPort<Float> { port(named: "inputTarget") }
    public var inputTriggerThreshold: ParameterPort<Float> { port(named: "inputTriggerThreshold") }
    public var inputReleaseThreshold: ParameterPort<Float> { port(named: "inputReleaseThreshold") }
    public var inputMinDurationSecs: ParameterPort<Float> { port(named: "inputMinDurationSecs") }
    public var outputValue: NodePort<Float> { port(named: "outputValue") }

    override public func startExecution(context: GraphExecutionContext) {
        self.state = 0
        self.triggerTime = 0
        self.hasEmitted = false
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let now = context.timing.time
        let target = self.inputTarget.value ?? 0
        let triggerThreshold = self.inputTriggerThreshold.value ?? 0
        let releaseThreshold = self.inputReleaseThreshold.value ?? 0
        let minDuration = TimeInterval(self.inputMinDurationSecs.value ?? 0)

        var newState = self.state
        if self.state == 0 {
            if target >= triggerThreshold {
                newState = 1
                self.triggerTime = now
            }
        } else {
            if target < releaseThreshold && self.triggerTime + minDuration < now {
                newState = 0
            }
        }

        if newState != self.state || !self.hasEmitted {
            self.state = newState
            self.hasEmitted = true
            self.outputValue.send(self.state)
        }
    }
}
