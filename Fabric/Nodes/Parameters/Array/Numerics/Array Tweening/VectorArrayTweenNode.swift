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
public class VectorArrayTweenNode<Value> : Node where Value: PortValueRepresentable & SIMD & Lerpable, Value.Scalar == Float
{
    override public class var name: String { "\(Value.portType.rawValue) Array Tween" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Tweens each element of a \(Value.portType.rawValue) array toward the matching Target over a duration using linear interpolation and an easing curve. All elements share one tween clock. When the Targets array changes, each element tweens from its current value; elements beyond the previous count start at their target." }

    public let inputTargets = NodePort<ContiguousArray<Value>>(name: "Targets", kind: .Inlet, description: "Per-element target value")
    public let inputDuration = ParameterPort(parameter: FloatParameter("Duration", 1.0, .inputfield, "Tween duration in seconds"))
    public let inputEasing = ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve"))
    public let outputValues = NodePort<ContiguousArray<Value>>(name: "Values", kind: .Outlet, description: "Current tweened values")
    public let outputProgress = NodePort<Float>(name: "Progress", kind: .Outlet, description: "Tween progress (0-1)")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputTargets", port: self.inputTargets),
            PortDeclaration(key: "inputDuration", port: self.inputDuration),
            PortDeclaration(key: "inputEasing", port: self.inputEasing),
            PortDeclaration(key: "outputValues", port: self.outputValues),
            PortDeclaration(key: "outputProgress", port: self.outputProgress),
        ]
    }

    private let driver = TweenArrayDriver<Value>()

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
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
