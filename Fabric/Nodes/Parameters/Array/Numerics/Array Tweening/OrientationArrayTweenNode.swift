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

    public var inputTargets: NodePort<ContiguousArray<simd_float4>> { _inputTargets }
    private var _inputTargets: NodePort<ContiguousArray<simd_float4>>!
    public var inputDuration: ParameterPort<Float> { _inputDuration }
    private var _inputDuration: ParameterPort<Float>!
    public var inputEasing: ParameterPort<String> { _inputEasing }
    private var _inputEasing: ParameterPort<String>!
    public var outputOrientations: NodePort<ContiguousArray<simd_float4>> { _outputOrientations }
    private var _outputOrientations: NodePort<ContiguousArray<simd_float4>>!
    public var outputProgress: NodePort<Float> { _outputProgress }
    private var _outputProgress: NodePort<Float>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._inputTargets = findPort(named: "inputTargets")
        self._inputDuration = findPort(named: "inputDuration")
        self._inputEasing = findPort(named: "inputEasing")
        self._outputOrientations = findPort(named: "outputOrientations")
        self._outputProgress = findPort(named: "outputProgress")
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
