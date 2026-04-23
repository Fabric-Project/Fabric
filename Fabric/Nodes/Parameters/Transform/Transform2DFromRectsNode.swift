//
//  Transform2DFromRectsNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class Transform2DFromRectsNode : Node
{
    override public class var name: String { "Transform2D From Rects" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Produces a 4x4 2D transform that maps any point inside Target Rect to the corresponding point inside Source Rect. Useful for 'take this region of the source and fit it to this region of the output' — e.g. Ken Burns over UVs (animate Source Rect) or per-strip scraping (one transform per strip, output rect to source rect). Rect format is (x, y, width, height). Target Rect defaults to the full unit square (0, 0, 1, 1)." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputSourceRect", ParameterPort(parameter: Float4Parameter("Source Rect", simd_float4(0, 0, 1, 1), .inputfield, "Rectangle in source space to sample from (x, y, width, height)"))),
            ("inputTargetRect", ParameterPort(parameter: Float4Parameter("Target Rect", simd_float4(0, 0, 1, 1), .inputfield, "Rectangle in target space to sample into (x, y, width, height). Defaults to the full unit square."))),
            ("outputTransform2D", NodePort<simd_float4x4>(name: "Transform2D", kind: .Outlet, description: "4x4 2D transform mapping Target Rect to Source Rect")),
        ]
    }

    public var inputSourceRect: ParameterPort<simd_float4> { port(named: "inputSourceRect") }
    public var inputTargetRect: ParameterPort<simd_float4> { port(named: "inputTargetRect") }
    public var outputTransform2D: NodePort<simd_float4x4> { port(named: "outputTransform2D") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputSourceRect.valueDidChange || self.inputTargetRect.valueDidChange else { return }

        let source = self.inputSourceRect.value ?? simd_float4(0, 0, 1, 1)
        let target = self.inputTargetRect.value ?? simd_float4(0, 0, 1, 1)

        // Degenerate target rect: emit identity rather than divide by zero.
        let eps: Float = 1e-8
        guard abs(target.z) > eps && abs(target.w) > eps else {
            self.outputTransform2D.send(matrix_identity_float4x4)
            return
        }

        // For target point (px, py) in Target Rect, the corresponding point in
        // Source Rect is:
        //   sx = source.x + (source.w / target.w) * (px - target.x)
        //   sy = source.y + (source.h / target.h) * (py - target.y)
        let sx = source.z / target.z
        let sy = source.w / target.w
        let tx = source.x - sx * target.x
        let ty = source.y - sy * target.y

        let m = simd_float4x4(
            simd_float4(sx, 0,  0, 0),
            simd_float4(0,  sy, 0, 0),
            simd_float4(0,  0,  1, 0),
            simd_float4(tx, ty, 0, 1)
        )
        self.outputTransform2D.send(m)
    }
}
