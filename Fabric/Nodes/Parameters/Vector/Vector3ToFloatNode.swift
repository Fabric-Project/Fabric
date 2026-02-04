//
//  Vector3ToFloatNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/16/25.
//

import Foundation
import Satin
import simd
import Metal

public class Vector3ToFloatNode : Node
{
    override public static var name:String { "Vector 3 to Float" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Converts a Vector 3 to its 3 numerical components"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputVectorParam",   ParameterPort(parameter:Float3Parameter("Vector 3", .zero, .inputfield, "Input vector to decompose into components"))),
            ("outputXPort",   NodePort<Float>(name: "X" , kind: .Outlet, description: "X component of the input vector") ),
            ("outputYPort",   NodePort<Float>(name: "Y" , kind: .Outlet, description: "Y component of the input vector") ),
            ("outputZPort",   NodePort<Float>(name: "Z" , kind: .Outlet, description: "Z component of the input vector") ),
        ]
    }

    // Port Proxies
    public var inputVectorParam:ParameterPort<simd_float3> { port(named: "inputVectorParam") }
    public var outputXPort:NodePort<Float> { port(named: "outputXPort") }
    public var outputYPort:NodePort<Float> { port(named: "outputYPort") }
    public var outputZPort:NodePort<Float> { port(named: "outputZPort") }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputVectorParam.valueDidChange,
           let inputVector = self.inputVectorParam.value
        {
            self.outputXPort.send( inputVector.x )
            self.outputYPort.send( inputVector.y )
            self.outputZPort.send( inputVector.z )
        }
     }
}
