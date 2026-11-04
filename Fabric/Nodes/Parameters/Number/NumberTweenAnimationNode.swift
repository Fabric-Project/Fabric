//
//  NumberTweenAnimationNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class NumberTweenNode : Node
{
    override public class var name:String { "Number Tween" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Tween toward a target value over a duration using an easing curve" }

    // Ports
    public let inputTarget = ParameterPort(parameter: FloatParameter("Target", 0.0, .inputfield, "The value to tween toward"))
    public let inputDuration = ParameterPort(parameter: FloatParameter("Duration", 1.0, .inputfield, "Tween duration in seconds"))
    public let inputEasing = ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve"))
    public let outputNumber = NodePort<Float>(name: "Number", kind: .Outlet, description: "Current tweened value")
    public let outputProgress = NodePort<Float>(name: "Progress", kind: .Outlet, description: "Tween progress (0-1)")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputTarget", port: self.inputTarget),
            PortDeclaration(key: "inputDuration", port: self.inputDuration),
            PortDeclaration(key: "inputEasing", port: self.inputEasing),
            PortDeclaration(key: "outputNumber", port: self.outputNumber),
            PortDeclaration(key: "outputProgress", port: self.outputProgress),
        ]
    }

    // Port Proxies

    // Tween state
    private var tween = TweenState()
    private var fromValue:Float = 0.0
    private var toValue:Float = 0.0
    private var currentOutput:Float = 0.0

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let time = executionInfo.timing.time

        // Detect target change → snap-retarget
        if self.inputTarget.valueDidChange,
           let newTarget = self.inputTarget.value
        {
            if !tween.initialized
            {
                currentOutput = newTarget
                toValue = newTarget
                tween.initialized = true
            }
            else if newTarget != toValue
            {
                fromValue = currentOutput
                toValue = newTarget
                tween.start(at: time)
            }
        }

        // Drive the tween
        if let duration = self.inputDuration.value,
           let easingName = self.inputEasing.value,
           let result = tween.update(time: time, duration: duration, easingName: easingName)
        {
            currentOutput = fromValue + (toValue - fromValue) * result.easedT

            if result.t >= 1.0
            {
                currentOutput = toValue
            }

            self.outputNumber.send(currentOutput)
            self.outputProgress.send(result.t)
        }
        else if tween.initialized
        {
            self.outputNumber.send(currentOutput)
            self.outputProgress.send(tween.tweening ? 0.0 : 1.0)
        }
    }
}
