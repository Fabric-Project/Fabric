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

    private let driver = TweenArrayDriver<Value>(interpolate: { $0 + ($1 - $0) * $2 })

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let time = executionInfo.timing.time

        if self.inputTargets.valueDidChange, let targets = self.inputTargets.value {
            driver.setTargets(Array(targets), at: time)
        }

        if let result = driver.update(time: time, duration: self.inputDuration.value, easingName: self.inputEasing.value) {
            self.outputValues.send(result.values)
            self.outputProgress.send(result.progress)
        }
    }
}
