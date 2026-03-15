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
    override public class var nodeDescription: String { "Wall-clock time as seconds since midnight" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("outputNumber", NodePort<Float>(name: NumberNode.name, kind: .Outlet, description: "Seconds elapsed since midnight")),
        ]
    }

    // Port proxies
    public var outputNumber: NodePort<Float> { port(named: "outputNumber") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now)
        let seconds = now.timeIntervalSince(midnight)
        outputNumber.send(Float(seconds))
    }
}
