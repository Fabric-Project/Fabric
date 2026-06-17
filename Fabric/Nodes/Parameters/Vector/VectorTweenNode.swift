//
//  VectorTweenNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// Tweens a single vector toward a target over a duration using linear
/// interpolation and an easing curve. The array equivalent is
/// VectorArrayTweenNode. Generic over simd_float2/3/4.
public class VectorTweenNode<Value> : Node where Value: PortValueRepresentable & SIMD & DefaultParameterProviding, Value.Scalar == Float
{
    override public class var name: String { "\(Value.portType.rawValue) Tween" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Tween toward a target \(Value.portType.rawValue) over a duration using linear interpolation and an easing curve" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputTarget", Value.makeDefaultParameterPort(name: "Target", description: "Target value to tween toward")),
            ("inputDuration", ParameterPort(parameter: FloatParameter("Duration", 1.0, .inputfield, "Tween duration in seconds"))),
            ("inputEasing", ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve"))),
            ("outputValue", NodePort<Value>(name: "Value", kind: .Outlet, description: "Current tweened value")),
            ("outputProgress", NodePort<Float>(name: "Progress", kind: .Outlet, description: "Tween progress (0-1)")),
        ]
    }

    // ParameterPort<T> is a subclass of NodePort<T>, so this accessor is
    // compatible whether the concrete value port is a ParameterPort or NodePort.
    public var inputTarget: NodePort<Value> { port(named: "inputTarget") }
    public var inputDuration: ParameterPort<Float> { port(named: "inputDuration") }
    public var inputEasing: ParameterPort<String> { port(named: "inputEasing") }
    public var outputValue: NodePort<Value> { port(named: "outputValue") }
    public var outputProgress: NodePort<Float> { port(named: "outputProgress") }

    private let driver = TweenDriver<Value>(interpolate: { $0 + ($1 - $0) * $2 })

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let time = executionInfo.timing.time

        if self.inputTarget.valueDidChange, let target = self.inputTarget.value {
            driver.setTarget(target, at: time)
        }

        if let result = driver.update(time: time, duration: self.inputDuration.value, easingName: self.inputEasing.value) {
            self.outputValue.send(result.value)
            self.outputProgress.send(result.progress)
        }
    }
}
