//
//  ColorPassThroughNode.swift
//  Fabric
//
//  Created by Claude on 4/11/26.
//

import Foundation
import Satin
import simd
import Metal

/// Patching utility node for Color ports. Uses a color picker for the input.
public class ColorPassThroughNode: Node
{
    override public class var name: String { "Color" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Patching utility for Color." }

    // If an instance has connections on its input port, it should be considered a Processor.
    override public var nodeExecutionMode: Node.ExecutionMode { self.input.connections.isEmpty ? .Provider : .Processor }

    // Ports
    public let input: NodePort<simd_float4> = ParameterPort(parameter: Float4Parameter("Color", simd_float4(0, 0, 0, 1), .colorpicker, "Input color (RGBA)"))
    public let output: NodePort<simd_float4> = ColorNodePort(name: "Color", kind: .Outlet, description: "Output color")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "input", port: self.input),
            PortDeclaration(key: "output", port: self.output),
        ]
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.input.valueDidChange
        {
            self.output.send(self.input.value)
        }
    }
}
