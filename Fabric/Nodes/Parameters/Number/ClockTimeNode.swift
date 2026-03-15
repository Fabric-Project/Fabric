//
//  ClockTimeNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class ClockTimeNode: Node {
    override public class var name: String { "Clock Time" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Wall-clock time as a Unix timestamp" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("outputNumber", NodePort<Float>(name: NumberNode.name, kind: .Outlet, description: "Unix timestamp (seconds since 1970-01-01)")),
        ]
    }

    // Port proxies
    public var outputNumber: NodePort<Float> { port(named: "outputNumber") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        outputNumber.send(Float(Date().timeIntervalSince1970))
    }
}
