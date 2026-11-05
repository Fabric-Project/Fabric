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
public class VectorTweenNode<Value> : Node where Value: PortValueRepresentable & SIMD & Lerpable & ParameterValueType, Value.Scalar == Float
{
    override public class var name: String { "\(Value.portType.rawValue) Tween" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Tween toward a target \(Value.portType.rawValue) over a duration using linear interpolation and an easing curve" }

    public let inputTarget = NodePort<Value>.makeFresh(name: "Target", kind: .Inlet, description: "Target value to tween toward")
    public let inputDuration = ParameterPort(parameter: FloatParameter("Duration", 1.0, .inputfield, "Tween duration in seconds"))
    public let inputEasing = ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve"))
    public let outputValue = NodePort<Value>(name: "Value", kind: .Outlet, description: "Current tweened value")
    public let outputProgress = NodePort<Float>(name: "Progress", kind: .Outlet, description: "Tween progress (0-1)")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputTarget", port: self.inputTarget),
            PortDeclaration(key: "inputDuration", port: self.inputDuration),
            PortDeclaration(key: "inputEasing", port: self.inputEasing),
            PortDeclaration(key: "outputValue", port: self.outputValue),
            PortDeclaration(key: "outputProgress", port: self.outputProgress),
        ]
    }

    // ParameterPort<T> is a subclass of NodePort<T>, so this accessor is
    // compatible whether the concrete value port is a ParameterPort or NodePort.

    private let driver = TweenDriver<Value>()

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
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
