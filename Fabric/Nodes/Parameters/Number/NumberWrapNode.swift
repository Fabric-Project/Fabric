//
//  NumberWrapNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class NumberWrapNode : Node
{
    override public class var name: String { "Wrap Number" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Rollover: wraps an input number into the closed interval [Min, Max]. Both bounds are inclusive — an input equal to Max passes through as Max (it does not roll over to Min). Period is Max − Min." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputNumber", ParameterPort(parameter: FloatParameter("Input Number", 0.0, .inputfield, "The input value to wrap"))),
            ("inputMinNumber", ParameterPort(parameter: FloatParameter("Min Number", 0.0, .inputfield, "Lower bound (inclusive)"))),
            ("inputMaxNumber", ParameterPort(parameter: FloatParameter("Max Number", 1.0, .inputfield, "Upper bound (inclusive)"))),
            ("outputNumber", NodePort<Float>(name: NumberNode.name, kind: .Outlet, description: "The wrapped output value, within [Min, Max]")),
        ]
    }

    public var inputNumber: ParameterPort<Float> { port(named: "inputNumber") }
    public var inputMinNumber: ParameterPort<Float> { port(named: "inputMinNumber") }
    public var inputMaxNumber: ParameterPort<Float> { port(named: "inputMaxNumber") }
    public var outputNumber: NodePort<Float> { port(named: "outputNumber") }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputNumber.valueDidChange
            || self.inputMinNumber.valueDidChange
            || self.inputMaxNumber.valueDidChange
        else { return }

        guard let x = self.inputNumber.value,
              let a = self.inputMinNumber.value,
              let b = self.inputMaxNumber.value
        else { return }

        let lo = Float.minimum(a, b)
        let hi = Float.maximum(a, b)
        let range = hi - lo

        // Degenerate interval: collapse to the bound.
        guard range > 0 else {
            self.outputNumber.send(lo)
            return
        }

        let delta = x - lo
        let k = floor(delta / range)
        let frac = delta - k * range

        // Exact multiples of the period above Min map to Max (inclusive upper
        // bound). Only x == Min itself returns Min; every other boundary value
        // maps to Max.
        if frac == 0 && delta != 0 {
            self.outputNumber.send(hi)
        } else {
            self.outputNumber.send(lo + frac)
        }
    }
}
