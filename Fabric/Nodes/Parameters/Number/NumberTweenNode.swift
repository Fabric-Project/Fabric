//
//  FloatTween.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//


import Foundation
import Satin
import simd
import Metal

public class NumberEaseNode : Node
{
    override public class var name:String { "Number Ease" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None } // TODO: Should this change?
    override public class var nodeDescription: String { "Run an easing on an input Number between 0 and 1 and return the resulting Eased Number"}

    // Ports
    public let inputNumber = ParameterPort(parameter: FloatParameter("Number", 0.0, .inputfield, "Normalized input value (0-1) to apply easing to"))
    public let inputParam = ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing function to apply to the input"))
    public let outputNumber = NodePort<Float>(name: "Number" , kind: .Outlet, description: "The eased output value")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputNumber", port: self.inputNumber),
            PortDeclaration(key: "inputParam", port: self.inputParam),
            PortDeclaration(key: "outputNumber", port: self.outputNumber),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputNumber.valueDidChange,
           let param = self.inputParam.value,
           let easeFunc = TweenEasing.map[param],
           let loopedTime = self.inputNumber.value//.truncatingRemainder(dividingBy: duration) // TODO: ?? should we loop by 1.0?
        {
            self.outputNumber.send( Float( easeFunc.function( Double(loopedTime) ) ) )
        }
     }
}

