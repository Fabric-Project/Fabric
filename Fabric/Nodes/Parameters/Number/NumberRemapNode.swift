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
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputNumber", ParameterPort(parameter: FloatParameter("Number", 0.0, .inputfield, "The input value to remap"))),
            ("inputMinNumber", ParameterPort(parameter: FloatParameter("Input Min", 0.0, .inputfield, "Minimum of the input range"))),
            ("inputMaxNumber", ParameterPort(parameter: FloatParameter("Input Max", 1.0, .inputfield, "Maximum of the input range"))),
            ("inputNewMinNumber", ParameterPort(parameter: FloatParameter("Output Min", 0.0, .inputfield, "Minimum of the output range"))),
            ("inputNewMaxNumber", ParameterPort(parameter: FloatParameter("Output Max", 1.0, .inputfield, "Maximum of the output range"))),
            ("inputClamp", ParameterPort(parameter: BoolParameter("Clamp", false, .toggle, "Respect the given ranges: inputs outside [Input Min, Input Max] map to the output min/max instead of extrapolating past them. Off by default."))),
            ("outputNumber", NodePort<Float>(name: "Number" , kind: .Outlet, description: "The remapped output value")),
        ]
    }

    // Port Proxy
    public var inputNumber: ParameterPort<Float> { _inputNumber }
    private var _inputNumber: ParameterPort<Float>!
    public var inputMinNumber: ParameterPort<Float> { _inputMinNumber }
    private var _inputMinNumber: ParameterPort<Float>!
    public var inputMaxNumber: ParameterPort<Float> { _inputMaxNumber }
    private var _inputMaxNumber: ParameterPort<Float>!
    public var inputNewMinNumber: ParameterPort<Float> { _inputNewMinNumber }
    private var _inputNewMinNumber: ParameterPort<Float>!
    public var inputNewMaxNumber: ParameterPort<Float> { _inputNewMaxNumber }
    private var _inputNewMaxNumber: ParameterPort<Float>!
    public var inputClamp: ParameterPort<Bool> { _inputClamp }
    private var _inputClamp: ParameterPort<Bool>!
    public var outputNumber: NodePort<Float> { _outputNumber }
    private var _outputNumber: NodePort<Float>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._inputNumber = findPort(named: "inputNumber")
        self._inputMinNumber = findPort(named: "inputMinNumber")
        self._inputMaxNumber = findPort(named: "inputMaxNumber")
        self._inputNewMinNumber = findPort(named: "inputNewMinNumber")
        self._inputNewMaxNumber = findPort(named: "inputNewMaxNumber")
        self._inputClamp = findPort(named: "inputClamp")
        self._outputNumber = findPort(named: "outputNumber")
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
