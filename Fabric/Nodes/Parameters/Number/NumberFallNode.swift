//
//  NumberFallNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal
import QuartzCore

public class NumberFallNode : Node
{
    override public class var name:String { "Fall Number" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Pass rising values through; smooth falling values (VU-meter style peak-with-decay)" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputNumber", ParameterPort(parameter: FloatParameter("Number", 0, .inputfield))),
            ("inputFrequency", ParameterPort(parameter: FloatParameter("Frequency", 4.0, .inputfield))),
            ("outputNumber", NodePort<Float>(name: NumberNode.name, kind: .Outlet)),
        ]
    }

    public var inputNumber:ParameterPort<Float> { port(named: "inputNumber") }
    public var inputFrequency:ParameterPort<Float> { port(named: "inputFrequency") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }

    private var lastOutput: Float = 0

    override public func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let input = self.inputNumber.value else { return }

        if input >= lastOutput {
            // Rising edge: pass through immediately.
            lastOutput = input
        } else {
            // Falling edge: exponential decay toward input. `Frequency` is
            // the decay rate (Hz); higher = faster fall. Default 4 Hz gives
            // a ~250 ms time constant — a comfortable VU-meter feel.
            let frequency = max(0.001, Double(self.inputFrequency.value ?? 4.0))
            let timeConstant = 1.0 / frequency
            let alpha = Float(1.0 - exp(-context.timing.deltaTime / timeConstant))
            lastOutput += alpha * (input - lastOutput)
        }

        self.outputNumber.send(lastOutput)
    }
}
