//
//  FloatAddNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/2/25.
//

import Foundation


import Foundation
import Satin
import simd
import Metal

public class SystemTimeNode : Node
{
    override public class var name:String { "System Time" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Elapsed system clock time in seconds since execution started" }

    private var startTime: TimeInterval?
    
    // Ports
    public let outputNumber = NodePort<Float>(name: "Number" , kind: .Outlet, description: "Elapsed system time in seconds since execution started")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "outputNumber", port: self.outputNumber),
        ]
    }

    override public func startExecution(renderer: GraphRenderer) throws
    {
        self.startTime = nil
        try super.startExecution(renderer: renderer)
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let currentTime = executionInfo.timing.systemTime
        let startTime = self.startTime ?? currentTime
        self.startTime = startTime
        self.outputNumber.send(Float(currentTime - startTime))
    }
}
