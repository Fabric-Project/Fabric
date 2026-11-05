//
//  CurrentTimeNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/2/25.
//

import Foundation
import Satin
import simd
import Metal

public class CurrentTimeNode : Node
{
    override public class var name:String { "Graph Time" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Elapsed time in seconds since graph execution started" }

    // Ports
    public let outputNumber = NodePort<Float>(name: "Seconds", kind: .Outlet, description: "Elapsed time in seconds since graph execution started")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "outputNumber", port: self.outputNumber),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        self.outputNumber.send(Float(executionInfo.timing.time))
    }
}
