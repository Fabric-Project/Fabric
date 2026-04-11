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

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("input", ParameterPort(parameter: Float4Parameter("Color", simd_float4(0, 0, 0, 1), .colorpicker, "Input color (RGBA)"))),
            ("output", NodePort<simd_float4>(name: "Color", kind: .Outlet, description: "Output color")),
        ]
    }

    // Port Proxy
    public var input: NodePort<simd_float4> { port(named: "input") }
    public var output: NodePort<simd_float4> { port(named: "output") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.output.send(self.input.value)
    }
}
