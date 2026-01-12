//
//  StringLengthNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class StringJoinNode : Node
{
    override public static var name:String { "String Join" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Join two Strings to make a new String"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort",   ParameterPort(parameter: StringParameter("String", "", .inputfield))),
            ("input2Port",  ParameterPort(parameter: StringParameter("String", "", .inputfield))),
            ("outputPort",  NodePort<String>(name: "String", kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<String>   { port(named: "inputPort") }
    public var input2Port:NodePort<String>   { port(named: "input2Port") }
    public var outputPort:NodePort<String>     { port(named: "outputPort") }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange || self.input2Port.valueDidChange
        {
            if let stringA = self.inputPort.value,
                let stringB = self.input2Port.value
            {
                self.outputPort.send( stringA + stringB )
            }
//            else
//            {
//                self.outputPort.send( nil )
//            }
        }
    }
}
