//
//  OrientationArrayTweenNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// Array equivalent of OrientationTweenNode: tweens each element of an
/// orientation array toward the corresponding Target using slerp and an easing
/// curve. All elements share one tween clock (Duration / Easing / Progress).
public class OrientationArrayTweenNode : Node
{
    override public class var name: String { "Orientation Array Tween" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Tweens each element of an orientation array toward the matching Target over a duration using slerp and an easing curve. All elements share one tween clock. When the Targets array changes, each element tweens from its current value; elements beyond the previous count start at their target." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputTargets", NodePort<ContiguousArray<simd_float4>>(name: "Targets", kind: .Inlet, description: "Per-element target quaternion orientation (X, Y, Z, W)")),
            ("inputDuration", ParameterPort(parameter: FloatParameter("Duration", 1.0, .inputfield, "Tween duration in seconds"))),
            ("inputEasing", ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve"))),
            ("outputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Current tweened orientations (X, Y, Z, W per element)")),
            ("outputProgress", NodePort<Float>(name: "Progress", kind: .Outlet, description: "Tween progress (0-1)")),
        ]
    }

    public var inputTargets: NodePort<ContiguousArray<simd_float4>> { port(named: "inputTargets") }
    public var inputDuration: ParameterPort<Float> { port(named: "inputDuration") }
    public var inputEasing: ParameterPort<String> { port(named: "inputEasing") }
    public var outputOrientations: NodePort<ContiguousArray<simd_float4>> { port(named: "outputOrientations") }
    public var outputProgress: NodePort<Float> { port(named: "outputProgress") }

    // Tween state (one clock shared across elements; per-element endpoints)
    private var tween = TweenState()
    private var fromQuats: [simd_quatf] = []
    private var toQuats: [simd_quatf] = []
    private var currentOutputs: [simd_quatf] = []
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
           let targetVecs = self.inputTargets.value
        {
            let newTargets = targetVecs.map { simd_quatf(safeVector: $0) }

            if !tween.initialized
            {
                fromQuats = newTargets
                toQuats = newTargets
                currentOutputs = newTargets
                tween.initialized = true
                pendingEmit = true
            }
            else if newTargets != toQuats
            {
                // Tween each element from its current value; elements beyond
                // the previous count start already at their target.
                var newFrom = [simd_quatf]()
                newFrom.reserveCapacity(newTargets.count)
                for i in 0..<newTargets.count {
                    newFrom.append(i < currentOutputs.count ? currentOutputs[i] : newTargets[i])
                }
                fromQuats = newFrom
                toQuats = newTargets
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
            var output = ContiguousArray<simd_float4>()
            output.reserveCapacity(toQuats.count)
            for i in 0..<toQuats.count
            {
                let c = result.t >= 1.0 ? toQuats[i] : simd_slerp(fromQuats[i], toQuats[i], result.easedT)
                currentOutputs[i] = c
                output.append(c.vector)
            }
            self.outputOrientations.send(output)
            self.outputProgress.send(result.t)
            pendingEmit = false
        }
        else if pendingEmit
        {
            // Emit the settled state once (after init / a retarget that didn't
            // tween), then stay quiet until something changes.
            if tween.initialized
            {
                var output = ContiguousArray<simd_float4>()
                output.reserveCapacity(currentOutputs.count)
                for c in currentOutputs { output.append(c.vector) }
                self.outputOrientations.send(output)
                self.outputProgress.send(tween.tweening ? 0.0 : 1.0)
            }
            else
            {
                // Targets unconnected / never received — emit an empty array so
                // downstream gets a value, like the other array nodes.
                self.outputOrientations.send(ContiguousArray<simd_float4>())
                self.outputProgress.send(1.0)
            }
            pendingEmit = false
        }
    }
}
