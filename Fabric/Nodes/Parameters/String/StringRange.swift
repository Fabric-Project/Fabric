//
//  StringRange.swift
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
    public let inputPort = ParameterPort(parameter: StringParameter("String", "", .inputfield, "Input string to extract substring from"))
    public let inputRangeFrom = ParameterPort(parameter: IntParameter("From", 0, .inputfield, "Start index for the substring"))
    public let inputRangeTo = ParameterPort(parameter: IntParameter("To", 1, .inputfield, "End index for the substring (exclusive)"))
    public let outputPort = NodePort<String>(name: "String", kind: .Outlet, description: "Extracted substring")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputPort", port: self.inputPort),
            PortDeclaration(key: "inputRangeFrom", port: self.inputRangeFrom),
            PortDeclaration(key: "inputRangeTo", port: self.inputRangeTo),
            PortDeclaration(key: "outputPort", port: self.outputPort),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputPort.valueDidChange || self.inputRangeFrom.valueDidChange || self.inputRangeTo.valueDidChange
        {
            if let string = self.inputPort.value,
               let rangeFrom = self.inputRangeFrom.value,
               let rangeTo = self.inputRangeTo.value
            {
                let fromOffset = max(0, rangeFrom)
                let toOffset = max(fromOffset, rangeTo)

                let startIndex = string.index(string.startIndex, offsetBy: fromOffset, limitedBy: string.endIndex) ?? string.endIndex
                let endIndex = string.index(string.startIndex, offsetBy: toOffset, limitedBy: string.endIndex) ?? string.endIndex

                self.outputPort.send( String(string[startIndex ..< endIndex]) )
            }
        }
    }
}
