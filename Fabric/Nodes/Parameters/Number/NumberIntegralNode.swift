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
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputNumber", ParameterPort(parameter: FloatParameter("Number", 0.0, .inputfield, "Value to integrate over time"))),
            ("outputNumber", NodePort<Float>(name: NumberNode.name , kind: .Outlet, description: "Accumulated sum of input values over time")),
        ]
    }
    
    // Port Proxy
    public var inputNumber:ParameterPort<Float> { port(named: "inputNumber") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.state += (self.inputNumber.value ?? 0.0) * -Float(context.timing.deltaTime)
        
        self.outputNumber.send(self.state)
    }
}
