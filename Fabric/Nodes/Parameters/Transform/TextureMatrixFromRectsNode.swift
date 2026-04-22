//
//  TextureMatrixFromRectsNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class TextureMatrixFromRectsNode : Node
{
    override public class var name: String { "Texture Matrix From Rects" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Produces a 4x4 texture matrix that maps any UV inside Target Rect to the corresponding UV inside Source Rect. Useful for 'sample this region of the source and fit it to this region of the output' — e.g. Ken Burns (animate Source Rect over time) or per-strip scraping (one matrix per strip, output rect to source rect). Rect format is (x, y, width, height) in UV space. Target Rect defaults to the full unit quad (0, 0, 1, 1)." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputSourceRect", ParameterPort(parameter: Float4Parameter("Source Rect", simd_float4(0, 0, 1, 1), .inputfield, "Rectangle in source UV space to sample from (x, y, width, height)"))),
            ("inputTargetRect", ParameterPort(parameter: Float4Parameter("Target Rect", simd_float4(0, 0, 1, 1), .inputfield, "Rectangle in output UV space to sample into (x, y, width, height). Defaults to the full unit quad."))),
            ("outputMatrix", NodePort<simd_float4x4>(name: "Texture Matrix", kind: .Outlet, description: "4x4 UV transform mapping Target Rect to Source Rect")),
        ]
    }

    public var inputSourceRect: ParameterPort<simd_float4> { port(named: "inputSourceRect") }
    public var inputTargetRect: ParameterPort<simd_float4> { port(named: "inputTargetRect") }
    public var outputMatrix: NodePort<simd_float4x4> { port(named: "outputMatrix") }

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
            self.outputMatrix.send(matrix_identity_float4x4)
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
        self.outputMatrix.send(m)
    }
}
