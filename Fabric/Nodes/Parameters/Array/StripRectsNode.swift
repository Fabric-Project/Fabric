//
//  StripRectsNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class StripRectsNode : Node
{
    public override class var name: String { "Strip Rects" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Builds an array of rects representing a horizontal strip layout. Starting at Origin, each element of Widths becomes a rect of the given Height, butted up against the previous one along +X. Output is shaped (x, y, width, height) per rect — plugs into Transforms Array From Rects and Transforms Array From Rect Pairs." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputOrigin", ParameterPort(parameter: Float2Parameter("Origin", .zero, .inputfield, "(X, Y) position of the first strip's bottom-left corner"))),
            ("inputHeight", ParameterPort(parameter: FloatParameter("Height", 1.0, .inputfield, "Height applied to every strip"))),
            ("inputWidths", NodePort<ContiguousArray<Float>>(name: "Widths", kind: .Inlet, description: "Per-strip width along +X. Output length matches this array.")),
            ("outputRects", NodePort<ContiguousArray<simd_float4>>(name: "Rects", kind: .Outlet, description: "Per-strip rect (x, y, width, height), laid out along +X")),
        ]
    }

    public var inputOrigin: ParameterPort<simd_float2> { port(named: "inputOrigin") }
    public var inputHeight: ParameterPort<Float> { port(named: "inputHeight") }
    public var inputWidths: NodePort<ContiguousArray<Float>> { port(named: "inputWidths") }
    public var outputRects: NodePort<ContiguousArray<simd_float4>> { port(named: "outputRects") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputOrigin.valueDidChange
            || self.inputHeight.valueDidChange
            || self.inputWidths.valueDidChange
        else { return }

        guard let widths = self.inputWidths.value, !widths.isEmpty else {
            self.outputRects.send(ContiguousArray<simd_float4>())
            return
        }

        let origin = self.inputOrigin.value ?? .zero
        let height = self.inputHeight.value ?? 1.0

        var output = ContiguousArray<simd_float4>()
        output.reserveCapacity(widths.count)
        var x = origin.x
        for width in widths {
            output.append(simd_float4(x, origin.y, width, height))
            x += width
        }
        self.outputRects.send(output)
    }
}
