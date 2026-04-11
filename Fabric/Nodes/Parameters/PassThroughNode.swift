//
//  PassThroughNode.swift
//  Fabric
//
//  Created by Claude on 4/11/26.
//

import Foundation
import Satin
import simd
import Metal

/// Patching utility node that passes a value through without modification.
/// Does not have editable inputs.
public class PassThroughNode<T: PortValueRepresentable>: Node
{
    override public class var name: String { T.portType.rawValue }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Patching utility for \(T.portType.rawValue). Does not have editable inputs." }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("input", NodePort<T>(name: T.portType.rawValue, kind: .Inlet, description: "Input \(T.portType.rawValue)")),
            ("output", NodePort<T>(name: T.portType.rawValue, kind: .Outlet, description: "Output \(T.portType.rawValue)")),
        ]
    }

    // Port Proxy
    public var input: NodePort<T> { port(named: "input") }
    public var output: NodePort<T> { port(named: "output") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.output.send(self.input.value)
    }
}
