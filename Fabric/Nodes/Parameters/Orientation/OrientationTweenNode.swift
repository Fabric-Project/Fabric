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
/// Connect an Orientation From Euler node or any other quaternion source
/// to the Target input. The tween follows the shortest rotation path.
public class OrientationTweenNode : Node
{
    override public class var name:String { "Orientation Tween" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Tween toward a target orientation over a duration using slerp and an easing curve" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputTarget", ParameterPort(parameter: Float4Parameter("Target", simd_float4(0, 0, 0, 1), .inputfield, "Target quaternion orientation (X, Y, Z, W)"))),
            ("inputDuration", ParameterPort(parameter: FloatParameter("Duration", 1.0, .inputfield, "Tween duration in seconds"))),
            ("inputEasing", ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve"))),
            ("outputOrientation", NodePort<simd_float4>(name: "Orientation", kind: .Outlet, description: "Current tweened quaternion orientation (X, Y, Z, W)")),
            ("outputProgress", NodePort<Float>(name: "Progress", kind: .Outlet, description: "Tween progress (0-1)")),
        ]
    }

    // Port Proxies
    public var inputTarget:ParameterPort<simd_float4> { port(named: "inputTarget") }
    public var inputDuration:ParameterPort<Float> { port(named: "inputDuration") }
    public var inputEasing:ParameterPort<String> { port(named: "inputEasing") }
    public var outputOrientation:NodePort<simd_float4> { port(named: "outputOrientation") }
    public var outputProgress:NodePort<Float> { port(named: "outputProgress") }

    // Interpolation is slerp; endpoints are stored as normalized quaternion
    // vectors so the shared driver can hold them as plain `simd_float4`.
    private let driver = TweenDriver<simd_float4>(interpolate: {
        simd_slerp(simd_quatf(vector: $0), simd_quatf(vector: $1), $2).vector
    })

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let time = executionInfo.timing.time

        if self.inputTarget.valueDidChange, let targetVec = self.inputTarget.value {
            driver.setTarget(simd_quatf(safeVector: targetVec).vector, at: time)
        }

        if let result = driver.update(time: time, duration: self.inputDuration.value, easingName: self.inputEasing.value) {
            self.outputOrientation.send(result.value)
            self.outputProgress.send(result.progress)
        }
    }
}
