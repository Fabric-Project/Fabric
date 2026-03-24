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
/// Connect an Euler Orientation node or any other quaternion source
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
            ("inputEasing", ParameterPort(parameter: StringParameter("Easing", "Linear", Easing.allCases.map( {$0.title()} ), .dropdown, "Easing curve"))),
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

    // Tween state
    private var tween = TweenState()
    private var fromQuat:simd_quatf = simd_quatf(angle: 0, axis: simd_float3(0, 1, 0))
    private var toQuat:simd_quatf = simd_quatf(angle: 0, axis: simd_float3(0, 1, 0))
    private var currentOutput:simd_quatf = simd_quatf(angle: 0, axis: simd_float3(0, 1, 0))

    override public func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let time = context.timing.time

        // Detect target change → snap-retarget
        if self.inputTarget.valueDidChange,
           let targetVec = self.inputTarget.value
        {
            let newTarget = simd_quatf(vector: targetVec).normalized

            if !tween.initialized
            {
                toQuat = newTarget
                currentOutput = newTarget
                tween.initialized = true
            }
            else if newTarget != toQuat
            {
                fromQuat = currentOutput
                toQuat = newTarget
                tween.start(at: time)
            }
        }

        // Drive the tween
        if let duration = self.inputDuration.value,
           let easingName = self.inputEasing.value,
           let result = tween.update(time: time, duration: duration, easingName: easingName)
        {
            currentOutput = simd_slerp(fromQuat, toQuat, result.easedT)

            if result.t >= 1.0
            {
                currentOutput = toQuat
            }

            self.outputOrientation.send(currentOutput.vector)
            self.outputProgress.send(result.t)
        }
        else if tween.initialized
        {
            self.outputOrientation.send(currentOutput.vector)
            self.outputProgress.send(tween.tweening ? 0.0 : 1.0)
        }
    }
}
