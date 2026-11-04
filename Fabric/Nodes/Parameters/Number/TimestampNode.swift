//
//  TimestampNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class TimestampNode: Node {
    override public class var name: String { "Timestamp" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Wall-clock time as a Unix timestamp" }

    // Ports
    public let outputSeconds = NodePort<Int>(name: "Seconds", kind: .Outlet, description: "Unix timestamp whole seconds since 1970-01-01")
    public let outputFraction = NodePort<Float>(name: "Fraction", kind: .Outlet, description: "Fractional second (0.0 to 1.0)")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "outputSeconds", port: self.outputSeconds),
            PortDeclaration(key: "outputFraction", port: self.outputFraction),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let timestamp = Date().timeIntervalSince1970
        outputSeconds.send(Int(timestamp))
        outputFraction.send(Float(timestamp - timestamp.rounded(.down)))
    }
}
