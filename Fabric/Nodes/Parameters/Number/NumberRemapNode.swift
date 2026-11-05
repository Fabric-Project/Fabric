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
    override public class var nodeDescription: String { "Remap a number from one range to another. With Clamp enabled, values outside the given ranges map to the range ends instead of extrapolating past them."}
    
    // Ports
    public let inputNumber = ParameterPort(parameter: FloatParameter("Number", 0.0, .inputfield, "The input value to remap"))
    public let inputMinNumber = ParameterPort(parameter: FloatParameter("Input Min", 0.0, .inputfield, "Minimum of the input range"))
    public let inputMaxNumber = ParameterPort(parameter: FloatParameter("Input Max", 1.0, .inputfield, "Maximum of the input range"))
    public let inputNewMinNumber = ParameterPort(parameter: FloatParameter("Output Min", 0.0, .inputfield, "Minimum of the output range"))
    public let inputNewMaxNumber = ParameterPort(parameter: FloatParameter("Output Max", 1.0, .inputfield, "Maximum of the output range"))
    public let inputClamp = ParameterPort(parameter: BoolParameter("Clamp", false, .toggle, "Respect the given ranges: inputs outside [Input Min, Input Max] map to the output min/max instead of extrapolating past them. Off by default."))
    public let outputNumber = NodePort<Float>(name: "Number" , kind: .Outlet, description: "The remapped output value")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputNumber", port: self.inputNumber),
            PortDeclaration(key: "inputMinNumber", port: self.inputMinNumber),
            PortDeclaration(key: "inputMaxNumber", port: self.inputMaxNumber),
            PortDeclaration(key: "inputNewMinNumber", port: self.inputNewMinNumber),
            PortDeclaration(key: "inputNewMaxNumber", port: self.inputNewMaxNumber),
            PortDeclaration(key: "inputClamp", port: self.inputClamp),
            PortDeclaration(key: "outputNumber", port: self.outputNumber),
        ]
    }

    private var lastValue:Float = 0.0
        
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
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
            // Clamp to whichever endpoint is the lower / upper bound, so an
            // inverted range (Input Min > Input Max) still clamps sensibly.
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
