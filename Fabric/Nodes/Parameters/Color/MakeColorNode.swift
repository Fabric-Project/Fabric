//
//  MakeColorNode.swift
//  Fabric
//
//  Created by Claude on 4/11/26.
//

import Foundation
import Satin
import simd
import Metal

/// Constructs a color from individual R, G, B, A float components.
public class MakeColorNode: Node
{
    override public class var name: String { "Make Color" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Color) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Converts 4 numerical components to a Color" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputR", ParameterPort(parameter: FloatParameter("R", 0.0, .inputfield, "Red component (0–1)"))),
            ("inputG", ParameterPort(parameter: FloatParameter("G", 0.0, .inputfield, "Green component (0–1)"))),
            ("inputB", ParameterPort(parameter: FloatParameter("B", 0.0, .inputfield, "Blue component (0–1)"))),
            ("inputA", ParameterPort(parameter: FloatParameter("A", 1.0, .inputfield, "Alpha component (0–1)"))),
            ("outputColor", NodePort<simd_float4>(name: "Color", kind: .Outlet, description: "Combined RGBA color")),
        ]
    }

    // Port Proxy
    public var inputR: ParameterPort<Float> { port(named: "inputR") }
    public var inputG: ParameterPort<Float> { port(named: "inputG") }
    public var inputB: ParameterPort<Float> { port(named: "inputB") }
    public var inputA: ParameterPort<Float> { port(named: "inputA") }
    public var outputColor: NodePort<simd_float4> { port(named: "outputColor") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputR.valueDidChange || self.inputG.valueDidChange || self.inputB.valueDidChange || self.inputA.valueDidChange,
           let r = self.inputR.value,
           let g = self.inputG.value,
           let b = self.inputB.value,
           let a = self.inputA.value
        {
            self.outputColor.send(simd_float4(r, g, b, a))
        }
    }
}
