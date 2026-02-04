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

public class StringRangeNode : Node
{
    override public static var name:String { "String Range" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Produce a Substring from a String"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort", NodePort<String>(name: "String", kind: .Inlet, description: "Input string to extract substring from")),
            ("inputRangeTo", ParameterPort(parameter: IntParameter("To", 0, .inputfield, "End index for the substring (exclusive)"))),
            ("outputPort",  NodePort<String>(name: "String", kind: .Outlet, description: "Extracted substring from start to specified index")),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<String> { port(named: "inputPort") }
    public var inputRangeTo:ParameterPort<Int> { port(named: "inputRangeTo") }
    public var outputPort:NodePort<String> { port(named: "outputPort") }


    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange || self.inputRangeTo.valueDidChange
        {
            if let string = self.inputPort.value,
               let rangeTo = self.inputRangeTo.value
            {
                let offset = max(0, rangeTo )
                let endIndex = string.index(string.startIndex, offsetBy:offset, limitedBy: string.endIndex)
                
                let substring = string[ string.startIndex ..< (endIndex ?? string.endIndex) ]
                
                self.outputPort.send( String(substring) )
            }
//            else
//            {
//                self.outputPort.send( nil )
//            }
        }
    }
}
