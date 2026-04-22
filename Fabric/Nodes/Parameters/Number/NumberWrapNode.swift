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
    override public class var nodeDescription: String { "Rollover: wraps an input number between Min and Max. Interval selects Closed [Min, Max] (inclusive — an input equal to Max passes through as Max) or Half-open [Min, Max) (Max wraps back to Min, standard modulo)." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputNumber", ParameterPort(parameter: FloatParameter("Input Number", 0.0, .inputfield, "The input value to wrap"))),
            ("inputMinNumber", ParameterPort(parameter: FloatParameter("Min Number", 0.0, .inputfield, "Lower bound (inclusive)"))),
            ("inputMaxNumber", ParameterPort(parameter: FloatParameter("Max Number", 1.0, .inputfield, "Upper bound (see Interval)"))),
            ("inputInterval", ParameterPort(parameter: StringParameter("Interval", "Closed", ["Closed", "Half-open"], .dropdown, "Closed: [Min, Max] — Max passes through. Half-open: [Min, Max) — Max wraps to Min."))),
            ("outputNumber", NodePort<Float>(name: NumberNode.name, kind: .Outlet, description: "The wrapped output value")),
        ]
    }

    public var inputNumber: ParameterPort<Float> { port(named: "inputNumber") }
    public var inputMinNumber: ParameterPort<Float> { port(named: "inputMinNumber") }
    public var inputMaxNumber: ParameterPort<Float> { port(named: "inputMaxNumber") }
    public var inputInterval: ParameterPort<String> { port(named: "inputInterval") }
    public var outputNumber: NodePort<Float> { port(named: "outputNumber") }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputNumber.valueDidChange
            || self.inputMinNumber.valueDidChange
            || self.inputMaxNumber.valueDidChange
            || self.inputInterval.valueDidChange
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

        let closed = self.inputInterval.value != "Half-open"
        if closed && frac == 0 && delta != 0 {
            // Closed interval: exact period multiples above Min map to Max
            // (except x == Min itself, which returns Min). Half-open falls
            // through to the standard modulo path.
            self.outputNumber.send(hi)
        } else {
            self.outputNumber.send(lo + frac)
        }
    }
}
