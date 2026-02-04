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

public class StringWrapNode : Node
{
    override public static var name:String { "String Wrap" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Wraps a String"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort", NodePort<String>(name: "String", kind: .Inlet, description: "Input string to wrap")),
            ("inputWordWrapCount", ParameterPort(parameter: IntParameter("Word Count", 10, .inputfield, "Number of words per line before wrapping"))),
            ("outputPort",  NodePort<String>(name: "String", kind: .Outlet, description: "String with newlines inserted at word wrap boundaries")),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<String> { port(named: "inputPort") }
    public var inputWordWrapCount:ParameterPort<Int> { port(named: "inputWordWrapCount") }
    public var outputPort:NodePort<String> { port(named: "outputPort") }


    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange || self.inputWordWrapCount.valueDidChange
        {
            if let string = self.inputPort.value,
               let wrapCount = self.inputWordWrapCount.value
            {
                let words = string.components(separatedBy: .whitespacesAndNewlines)
               
                var outputString:String = ""
                
                var lastLineOutput = 0

                for line in stride(from: 0, to: words.count, by: wrapCount)
                {
                    let lineWords = words[lastLineOutput ..< line]
                    
                    outputString.append( lineWords.joined(separator: " "))
                    outputString.append( "\n" )
                    
                    lastLineOutput = line
                }
               
                let diff = words.count - lastLineOutput
                
                let lastLineWords = words[lastLineOutput ..< (lastLineOutput + diff)]
                
                outputString.append(lastLineWords.joined(separator: " "))
                
                self.outputPort.send( outputString )
            }
//            else
//            {
//                self.outputPort.send( nil )
//            }
        }
    }
}
