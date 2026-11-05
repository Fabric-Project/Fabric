//
//  OrientationTweenNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// Tweens toward a target quaternion orientation over a duration using
/// spherical linear interpolation (slerp) and an easing curve.
///
/// Connect a Compose Orientation node or any other quaternion source
/// to the Target input. The tween follows the shortest rotation path.
public class OrientationTweenNode : Node
{
    override public class var name:String { "Orientation Tween" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Tween toward a target orientation over a duration using slerp and an easing curve" }

    // Ports
    public let inputTarget = ParameterPort(parameter: Float4Parameter("Target", simd_float4(0, 0, 0, 1), .inputfield, "Target quaternion orientation (X, Y, Z, W)"))
    public let inputDuration = ParameterPort(parameter: FloatParameter("Duration", 1.0, .inputfield, "Tween duration in seconds"))
    public let inputEasing = ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve"))
    public let outputOrientation = NodePort<simd_float4>(name: "Orientation", kind: .Outlet, description: "Current tweened quaternion orientation (X, Y, Z, W)")
    public let outputProgress = NodePort<Float>(name: "Progress", kind: .Outlet, description: "Tween progress (0-1)")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputTarget", port: self.inputTarget),
            PortDeclaration(key: "inputDuration", port: self.inputDuration),
            PortDeclaration(key: "inputEasing", port: self.inputEasing),
            PortDeclaration(key: "outputOrientation", port: self.outputOrientation),
            PortDeclaration(key: "outputProgress", port: self.outputProgress),
        ]
    }

    // Port Proxies

    // Quaternions, so the driver slerps; the ports carry them as float4.
    private let driver = TweenDriver<simd_quatf>()

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let time = executionInfo.timing.time

        if self.inputTarget.valueDidChange, let targetVec = self.inputTarget.value {
            driver.setTarget(simd_quatf(safeVector: targetVec), at: time)
        }

        if let result = driver.update(time: time, duration: self.inputDuration.value, easingName: self.inputEasing.value) {
            self.outputOrientation.send(result.value.vector)
            self.outputProgress.send(result.progress)
        }
    }
}
