//
//  VectorArrayTweenNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// Array equivalent of VectorTweenNode: tweens each element of a vector array
/// toward the matching Target using linear interpolation and an easing curve.
/// All elements share one tween clock (Duration / Easing / Progress).
public class VectorArrayTweenNode<Value> : Node where Value: PortValueRepresentable & SIMD, Value.Scalar == Float
{
    override public class var name: String { "\(Value.portType.rawValue) Array Tween" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Tweens each element of a \(Value.portType.rawValue) array toward the matching Target over a duration using linear interpolation and an easing curve. All elements share one tween clock. When the Targets array changes, each element tweens from its current value; elements beyond the previous count start at their target." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputTargets", NodePort<ContiguousArray<Value>>(name: "Targets", kind: .Inlet, description: "Per-element target value")),
            ("inputDuration", ParameterPort(parameter: FloatParameter("Duration", 1.0, .inputfield, "Tween duration in seconds"))),
            ("inputEasing", ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve"))),
            ("outputValues", NodePort<ContiguousArray<Value>>(name: "Values", kind: .Outlet, description: "Current tweened values")),
            ("outputProgress", NodePort<Float>(name: "Progress", kind: .Outlet, description: "Tween progress (0-1)")),
        ]
    }

    public var inputTargets: NodePort<ContiguousArray<Value>> { port(named: "inputTargets") }
    public var inputDuration: ParameterPort<Float> { port(named: "inputDuration") }
    public var inputEasing: ParameterPort<String> { port(named: "inputEasing") }
    public var outputValues: NodePort<ContiguousArray<Value>> { port(named: "outputValues") }
    public var outputProgress: NodePort<Float> { port(named: "outputProgress") }

    // Tween state (one clock shared across elements; per-element endpoints)
    private var tween = TweenState()
    private var fromValues: [Value] = []
    private var toValues: [Value] = []
    private var currentOutputs: [Value] = []
    // Emit on the next idle frame after a state change; avoids re-sending the
    // whole array every frame while at rest. Starts true so the first frame
    // emits (an empty array when Targets is unconnected).
    private var pendingEmit = true

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let time = executionInfo.timing.time

        // Detect target change → snap-retarget
        if self.inputTargets.valueDidChange,
           let targetVals = self.inputTargets.value
        {
            let newTargets = Array(targetVals)

            if !tween.initialized
            {
                fromValues = newTargets
                toValues = newTargets
                currentOutputs = newTargets
                tween.initialized = true
                pendingEmit = true
            }
            else if newTargets != toValues
            {
                // Tween each element from its current value; elements beyond
                // the previous count start already at their target.
                var newFrom = [Value]()
                newFrom.reserveCapacity(newTargets.count)
                for i in 0..<newTargets.count {
                    newFrom.append(i < currentOutputs.count ? currentOutputs[i] : newTargets[i])
                }
                fromValues = newFrom
                toValues = newTargets
                currentOutputs = newFrom
                tween.start(at: time)
                pendingEmit = true
            }
        }

        // Drive the tween
        if let duration = self.inputDuration.value,
           let easingName = self.inputEasing.value,
           let result = tween.update(time: time, duration: duration, easingName: easingName)
        {
            var output = ContiguousArray<Value>()
            output.reserveCapacity(toValues.count)
            for i in 0..<toValues.count
            {
                let c = result.t >= 1.0 ? toValues[i] : fromValues[i] + (toValues[i] - fromValues[i]) * result.easedT
                currentOutputs[i] = c
                output.append(c)
            }
            self.outputValues.send(output)
            self.outputProgress.send(result.t)
            pendingEmit = false
        }
        else if pendingEmit
        {
            if tween.initialized
            {
                var output = ContiguousArray<Value>()
                output.reserveCapacity(currentOutputs.count)
                for c in currentOutputs { output.append(c) }
                self.outputValues.send(output)
                self.outputProgress.send(tween.tweening ? 0.0 : 1.0)
            }
            else
            {
                self.outputValues.send(ContiguousArray<Value>())
                self.outputProgress.send(1.0)
            }
            pendingEmit = false
        }
    }
}
