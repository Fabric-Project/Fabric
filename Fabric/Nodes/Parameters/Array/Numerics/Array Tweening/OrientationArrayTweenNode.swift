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
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Quaternion) }
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

    // Interpolation is slerp; endpoints are stored as normalized quaternion
    // vectors so the shared driver can hold them as plain `simd_float4`.
    private let driver = TweenArrayDriver<simd_float4>(interpolate: {
        simd_slerp(simd_quatf(vector: $0), simd_quatf(vector: $1), $2).vector
    })

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let time = executionInfo.timing.time

        if self.inputTargets.valueDidChange, let targets = self.inputTargets.value {
            // Normalize each target quaternion up front; the driver then slerps
            // unit quaternions and stores them as packed float4.
            driver.setTargets(targets.map { simd_quatf(safeVector: $0).vector }, at: time)
        }

        if let result = driver.update(time: time, duration: self.inputDuration.value, easingName: self.inputEasing.value) {
            self.outputOrientations.send(result.values)
            self.outputProgress.send(result.progress)
        }
    }
}
