//
//  Vector4ToFloatNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/16/25.
//

import Foundation
import Satin
import simd
import Metal

public class Vector4ToFloatNode : Node
{
    override public static var name:String { "Vector 4 to Float" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Converts a Vector 4 to its 4 numerical components"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputVectorParam",   ParameterPort(parameter:Float4Parameter("Vector 4", .zero, .inputfield))),
            ("outputXPort",   NodePort<Float>(name: "X" , kind: .Outlet) ),
            ("outputYPort",   NodePort<Float>(name: "Y" , kind: .Outlet) ),
            ("outputZPort",   NodePort<Float>(name: "Z" , kind: .Outlet) ),
            ("outputWPort",   NodePort<Float>(name: "W" , kind: .Outlet) ),
        ]
    }

    // Port Proxies
    public var inputVectorParam:ParameterPort<simd_float4> { port(named: "inputVectorParam") }
    public var outputXPort:NodePort<Float> { port(named: "outputXPort") }
    public var outputYPort:NodePort<Float> { port(named: "outputYPort") }
    public var outputZPort:NodePort<Float> { port(named: "outputZPort") }
    public var outputWPort:NodePort<Float> { port(named: "outputWPort") }
    
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
            self.outputWPort.send( inputVector.w )
        }
    }
}
