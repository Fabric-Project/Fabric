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
import QuartzCore

public class CurrentTimeNode : Node
{
    override public class var name:String { "Graph Time" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Elapsed time in seconds since graph execution started" }

    private var startTime:TimeInterval = 0

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("outputNumber", NodePort<Float>(name: "Seconds", kind: .Outlet, description: "Elapsed time in seconds since graph execution started")),
        ]
    }
    
    // Port Proxy
    public var inputNumber:ParameterPort<Float> { port(named: "inputNumber") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }
    
    override public func startExecution(renderer: GraphRenderer) throws
    {
        self.startTime = CACurrentMediaTime()
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        self.outputNumber.send( Float(executionInfo.timing.time - startTime) )
    }
}
