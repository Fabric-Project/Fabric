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
/// Uses an editable parameter port for the input when the type supports it.
public class PassThroughNode<T: PortValueRepresentable>: Node
{
    override public class var name: String { T.portType.rawValue }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Patching utility for \(T.portType.rawValue)." }

    // If an instance has connections on its input port, it should be considered a Processor.
    override public var nodeExecutionMode: Node.ExecutionMode { self.input.connections.isEmpty ? .Provider : .Processor }
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        let inputPort: Port
        if let editable = T.self as? any ParameterValueType.Type {
            inputPort = editable.makeDefaultParameterPort(
                name: T.portType.rawValue,
                description: "Input \(T.portType.rawValue)"
            )
        } else {
            inputPort = NodePort<T>(name: T.portType.rawValue, kind: .Inlet, description: "Input \(T.portType.rawValue)")
        }

        return ports +
        [
            ("input", inputPort),
            ("output", NodePort<T>(name: T.portType.rawValue, kind: .Outlet, description: "Output \(T.portType.rawValue)")),
        ]
    }
    
    override public required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
    }
    
    public required init(context: Context) {
        super.init(context: context)
    }
    
    // Port Proxy
    public var input: NodePort<T> { port(named: "input") }
    public var output: NodePort<T> { port(named: "output") }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        switch self.nodeExecutionMode
        {
        case .Provider, .Consumer:
            self.output.send(self.input.value)
            
        case .Processor:
            if self.input.valueDidChange
            {
                self.output.send(self.input.value)
            }
        }
    }
}
