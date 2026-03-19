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
            ("outputSeconds", NodePort<Int>(name: "Seconds", kind: .Outlet, description: "Unix timestamp whole seconds since 1970-01-01")),
            ("outputFraction", NodePort<Float>(name: "Fraction", kind: .Outlet, description: "Fractional second (0.0 to 1.0)")),
        ]
    }

    // Port proxies
    public var outputSeconds: NodePort<Int> { port(named: "outputSeconds") }
    public var outputFraction: NodePort<Float> { port(named: "outputFraction") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        let timestamp = Date().timeIntervalSince1970
        outputSeconds.send(Int(timestamp))
        outputFraction.send(Float(timestamp - timestamp.rounded(.down)))
    }
}
