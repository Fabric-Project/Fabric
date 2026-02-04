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

public class NumberNode : Node
{
    override public class var name:String { "Number" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provide a constant Number"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputNumber", ParameterPort(parameter: FloatParameter("Number", 0.0, .inputfield, "The constant number value to output"))),
            ("outputNumber", NodePort<Float>(name: NumberNode.name , kind: .Outlet, description: "The output number value")),
        ]
    }
    
    // Port Proxy
    public var inputNumber:ParameterPort<Float> { port(named: "inputNumber") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }

    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.outputNumber.send(self.inputNumber.value)
    }
}
