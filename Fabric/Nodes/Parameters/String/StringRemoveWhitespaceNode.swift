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

public class StringRemoveWhitespaceNode : Node
{
    override public static var name:String { "String Whitespace Remove" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Remove Whitespace from a String"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort", NodePort<String>(name: "String", kind: .Inlet)),
            ("outputPort",  NodePort<String>(name: "String", kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<String> { port(named: "inputPort") }
    public var outputPort:NodePort<String> { port(named: "outputPort") }


    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange
        {
            if let string = self.inputPort.value
            {
                self.outputPort.send( string.trimmingCharacters(in: .whitespacesAndNewlines) )
            }
//            else
//            {
//                self.outputPort.send( nil )
//            }
        }
    }
}
