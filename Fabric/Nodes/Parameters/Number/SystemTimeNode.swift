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
import QuartzCore

public class SystemTimeNode : Node
{
    override public class var name:String { "System Time" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Elapsed system clock time in seconds since execution started" }

    private var startTime:TimeInterval = 0
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("outputNumber", NodePort<Float>(name: "Number" , kind: .Outlet, description: "Elapsed system time in seconds since execution started")),
        ]
    }
    
    // Port Proxy
    public var inputNumber:ParameterPort<Float> { port(named: "inputNumber") }
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }
    
    override public func startExecution(renderer: GraphRenderer) throws
    {
        self.startTime = Date.timeIntervalSinceReferenceDate// context.timing.systemTime
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        self.outputNumber.send( Float(executionInfo.timing.systemTime - startTime) )
    }
}
