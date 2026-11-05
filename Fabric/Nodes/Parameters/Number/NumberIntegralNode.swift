//
//  NumberNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/2/25.
//

import Foundation
import Satin
import simd
import Metal

public class NumberIntegralNode : Node
{
    override public static var name:String { "Number Integral" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Integrates an input number every frame, and outputs the Integral"}
    
    // Ensure we always render!
    public override var isDirty:Bool { get {  true  } set { } }

    private var state:Float = 0.0
    
    // Ports
    public let inputNumber = ParameterPort(parameter: FloatParameter("Number", 0.0, .inputfield, "Value to integrate over time"))
    public let inputReset = ParameterPort(parameter: BoolParameter("Reset", false, .button, "Hold the Integral at zero while on"))
    public let outputNumber = NodePort<Float>(name: "Number" , kind: .Outlet, description: "Accumulated sum of input values over time")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputNumber", port: self.inputNumber),
            PortDeclaration(key: "inputReset", port: self.inputReset),
            PortDeclaration(key: "outputNumber", port: self.outputNumber),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputReset.value == true
        {
            self.state = 0.0
        }
        else
        {
            self.state += (self.inputNumber.value ?? 0.0) * Float(executionInfo.timing.deltaTime)
        }
        
        self.outputNumber.send(self.state)
    }
}
