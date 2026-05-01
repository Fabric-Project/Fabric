//
//  TransformsArrayFromRectPairsNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class TransformsArrayFromRectPairsNode : Node
{
    override public class var name: String { "Transforms Array From Rect Pairs" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Per-element version of Transform From Rects: given parallel arrays of source rects and target rects (one source/target pair per element), emits an array of 2D affine transforms, each mapping its Target Rect to its Source Rect. Output length matches the longest input; shorter inputs pad with their last element. Defaults per-element: both rects (0, 0, 1, 1)." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputSourceRects", NodePort<ContiguousArray<simd_float4>>(name: "Source Rects", kind: .Inlet, description: "Per-element source rect (x, y, width, height)")),
            ("inputTargetRects", NodePort<ContiguousArray<simd_float4>>(name: "Target Rects", kind: .Inlet, description: "Per-element target rect (x, y, width, height)")),
            ("outputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Outlet, description: "Array of 2D affine transforms")),
        ]
    }

    public var inputSourceRects: NodePort<ContiguousArray<simd_float4>> { port(named: "inputSourceRects") }
    public var inputTargetRects: NodePort<ContiguousArray<simd_float4>> { port(named: "inputTargetRects") }
    public var outputTransforms: NodePort<ContiguousArray<simd_float4x4>> { port(named: "outputTransforms") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputSourceRects.valueDidChange || self.inputTargetRects.valueDidChange else { return }

        let sourcesIn = self.inputSourceRects.value
        let targetsIn = self.inputTargetRects.value

        let count = [sourcesIn?.count ?? 0, targetsIn?.count ?? 0].max() ?? 0
        guard count > 0 else {
            self.outputTransforms.send(ContiguousArray<simd_float4x4>())
            return
        }

        let fallback = simd_float4(0, 0, 1, 1)
        let sources = padLast(sourcesIn, count: count, fallback: fallback)
        let targets = padLast(targetsIn, count: count, fallback: fallback)

        let eps: Float = 1e-8
        var output = ContiguousArray<simd_float4x4>()
        output.reserveCapacity(count)
        for i in 0..<count {
            let source = sources[i]
            let target = targets[i]

            if abs(target.z) < eps || abs(target.w) < eps {
                output.append(matrix_identity_float4x4)
                continue
            }

            let sx = source.z / target.z
            let sy = source.w / target.w
            let tx = source.x - sx * target.x
            let ty = source.y - sy * target.y

            output.append(simd_float4x4(
                simd_float4(sx, 0,  0, 0),
                simd_float4(0,  sy, 0, 0),
                simd_float4(0,  0,  1, 0),
                simd_float4(tx, ty, 0, 1)
            ))
        }
        self.outputTransforms.send(output)
    }

    @inline(__always)
    private func padLast<T>(_ array: ContiguousArray<T>?, count: Int, fallback: T) -> [T] {
        guard let array, !array.isEmpty else {
            return Array(repeating: fallback, count: count)
        }
        if array.count >= count { return Array(array.prefix(count)) }
        return Array(array) + Array(repeating: array.last!, count: count - array.count)
    }
}
