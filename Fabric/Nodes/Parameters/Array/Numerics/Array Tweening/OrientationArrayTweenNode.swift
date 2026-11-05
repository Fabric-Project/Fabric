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

    public let inputTargets = NodePort<ContiguousArray<simd_float4>>(name: "Targets", kind: .Inlet, description: "Per-element target quaternion orientation (X, Y, Z, W)")
    public let inputDuration = ParameterPort(parameter: FloatParameter("Duration", 1.0, .inputfield, "Tween duration in seconds"))
    public let inputEasing = ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve"))
    public let outputOrientations = NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Current tweened orientations (X, Y, Z, W per element)")
    public let outputProgress = NodePort<Float>(name: "Progress", kind: .Outlet, description: "Tween progress (0-1)")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputTargets", port: self.inputTargets),
            PortDeclaration(key: "inputDuration", port: self.inputDuration),
            PortDeclaration(key: "inputEasing", port: self.inputEasing),
            PortDeclaration(key: "outputOrientations", port: self.outputOrientations),
            PortDeclaration(key: "outputProgress", port: self.outputProgress),
        ]
    }

    // Quaternions, so the driver slerps; the ports carry them as float4.
    private let driver = TweenArrayDriver<simd_quatf>()

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let time = executionInfo.timing.time

        if self.inputTargets.valueDidChange, let targets = self.inputTargets.value {
            driver.setTargets(targets.map { simd_quatf(safeVector: $0) }, at: time)
        }

        if let result = driver.update(time: time, duration: self.inputDuration.value, easingName: self.inputEasing.value) {
            self.outputOrientations.send(ContiguousArray(result.values.lazy.map(\.vector)))
            self.outputProgress.send(result.progress)
        }
    }
}
