//
//  ConvertToStringNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class ConvertToStringNode : Node
{
    override public static var name:String { "Convert To String" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Convert any value to an appropriate String"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort", NodePort<AnyLoggable>(name: "Any", kind: .Inlet)),
            ("outputPort",  NodePort<String>(name: "String", kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<AnyLoggable> { port(named: "inputPort") }
    public var outputPort:NodePort<String> { port(named: "outputPort") }

    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange,
           let value = self.inputPort.value
        {
            self.outputPort.send( String(describing:value) )
        }
    }
}
