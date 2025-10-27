//
//  Vector2ToFloatNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/16/25.
//

import Foundation
import Satin
import simd
import Metal

public class Vector2ToFloatNode : Node
{
    override public static var name:String { "Vector 2 to Float" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Converts a Vector 2 to its 2 numerical components"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputVectorParam",   ParameterPort(parameter:Float3Parameter("Vector 2", .zero, .inputfield))),
            ("outputXPort",   NodePort<Float>(name: "X" , kind: .Outlet) ),
            ("outputYPort",   NodePort<Float>(name: "Y" , kind: .Outlet) ),
        ]
    }

    // Port Proxies
    public var inputVectorParam:ParameterPort<simd_float3> { port(named: "inputVectorParam") }
    public var outputXPort:NodePort<Float> { port(named: "outputXPort") }
    public var outputYPort:NodePort<Float> { port(named: "outputYPort") }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputVectorParam.valueDidChange,
           let inputVector = self.inputVectorParam.value
        {
            self.outputXPort.send( inputVector.x )
            self.outputYPort.send( inputVector.y )
        }
     }
}
