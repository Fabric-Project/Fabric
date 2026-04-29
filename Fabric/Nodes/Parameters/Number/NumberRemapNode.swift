//
//  NumberRemapRange.swift
//  Fabric
//
//  Created by Anton Marini on 5/22/25.
//

import Foundation
import Satin
import Metal

public class NumberRemapNode : Node
{
    override public static var name:String { "Number Remap" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Remap a number from one range to another. With Clamp Input enabled, values outside [Input Min, Input Max] are clamped before mapping; otherwise they're linearly extrapolated."}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputNumber", ParameterPort(parameter: FloatParameter("Number", 0.0, .inputfield, "The input value to remap"))),
            ("inputMinNumber", ParameterPort(parameter: FloatParameter("Input Min", 0.0, .inputfield, "Minimum of the input range"))),
            ("inputMaxNumber", ParameterPort(parameter: FloatParameter("Input Max", 1.0, .inputfield, "Maximum of the input range"))),
            ("inputNewMinNumber", ParameterPort(parameter: FloatParameter("Output Min", 0.0, .inputfield, "Minimum of the output range"))),
            ("inputNewMaxNumber", ParameterPort(parameter: FloatParameter("Output Max", 1.0, .inputfield, "Maximum of the output range"))),
            ("inputClamp", ParameterPort(parameter: BoolParameter("Clamp Input", false, .toggle, "Clamp the input to [Input Min, Input Max] before remapping. With clamp off (default), values outside the input range are linearly extrapolated past the output range."))),
            ("outputNumber", NodePort<Float>(name: "Number" , kind: .Outlet, description: "The remapped output value")),
        ]
    }

    // Port Proxy
    public var inputNumber:ParameterPort<Float> { port(named: "inputNumber") }
    public var inputMinNumber:ParameterPort<Float> { port(named: "inputMinNumber") }
    public var inputMaxNumber:ParameterPort<Float> { port(named: "inputMaxNumber") }
    public var inputNewMinNumber:ParameterPort<Float> { port(named: "inputNewMinNumber") }
    public var inputNewMaxNumber:ParameterPort<Float> { port(named: "inputNewMaxNumber") }
    public var inputClamp:ParameterPort<Bool> { port(named: "inputClamp") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }

    private var lastValue:Float = 0.0

    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputNumber.valueDidChange ||
            self.inputMinNumber.valueDidChange ||
            self.inputMaxNumber.valueDidChange ||
            self.inputNewMinNumber.valueDidChange ||
            self.inputNewMaxNumber.valueDidChange ||
            self.inputClamp.valueDidChange,
           let inputNumber = self.inputNumber.value,
           let inputMin = self.inputMinNumber.value,
           let inputMax = self.inputMaxNumber.value,
           let outputMin = self.inputNewMinNumber.value,
           let outputMax = self.inputNewMaxNumber.value
        {
            // Clamp to whichever endpoint is the lower / upper bound,
            // so an inverted range (Input Min > Input Max) still
            // clamps sensibly.
            let value: Float
            if self.inputClamp.value ?? false {
                let lo = Swift.min(inputMin, inputMax)
                let hi = Swift.max(inputMin, inputMax)
                value = Swift.max(lo, Swift.min(hi, inputNumber))
            } else {
                value = inputNumber
            }

            self.lastValue = remap(value,
                                   inputMin,
                                   inputMax,
                                   outputMin,
                                   outputMax)

            self.outputNumber.send( self.lastValue )
        }
    }
}
