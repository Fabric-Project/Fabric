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
    override public class var nodeDescription: String { "Remap a number from one range to another."}
    
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
            ("outputNumber", NodePort<Float>(name: NumberNode.name , kind: .Outlet, description: "The remapped output value")),
        ]
    }
    
    // Port Proxy
    public var inputNumber:ParameterPort<Float> { port(named: "inputNumber") }
    public var inputMinNumber:ParameterPort<Float> { port(named: "inputMinNumber") }
    public var inputMaxNumber:ParameterPort<Float> { port(named: "inputMaxNumber") }
    public var inputNewMinNumber:ParameterPort<Float> { port(named: "inputNewMinNumber") }
    public var inputNewMaxNumber:ParameterPort<Float> { port(named: "inputNewMaxNumber") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }
    
    private let easingMap = Dictionary(uniqueKeysWithValues: zip(Easing.allCases.map( {$0.title()}), Easing.allCases)  )

    private var lastValue:Float = 0.0
        
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputNumber.valueDidChange ||
            self.inputMinNumber.valueDidChange ||
            self.inputMaxNumber.valueDidChange ||
            self.inputNewMinNumber.valueDidChange ||
            self.inputNewMaxNumber.valueDidChange,
           let inputNumber = self.inputNumber.value,
           let inputMin = self.inputMinNumber.value,
           let inputMax = self.inputMaxNumber.value,
           let outputMin = self.inputNewMinNumber.value,
           let outputMax = self.inputNewMaxNumber.value
        {
            self.lastValue = remap(inputNumber,
                                   inputMin,
                                   inputMax,
                                   outputMin,
                                   outputMax)
            
            self.outputNumber.send( self.lastValue )
        }
    }
}
