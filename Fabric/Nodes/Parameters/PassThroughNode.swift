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
/// Its input is whatever the port factory makes for the type: a parameter
/// port where the type can carry one, otherwise a plain port at its resting value.
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
    public let input = NodePort<T>.makeFresh(name: T.portType.rawValue, kind: .Inlet, description: "Input \(T.portType.rawValue)")
    public let output = NodePort<T>.makeFresh(name: T.portType.rawValue, kind: .Outlet, description: "Output \(T.portType.rawValue)")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "input", port: self.input),
            PortDeclaration(key: "output", port: self.output),
        ]
    }
    
    override public required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
    }
    
    public required init(context: Context) {
        super.init(context: context)
    }

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
