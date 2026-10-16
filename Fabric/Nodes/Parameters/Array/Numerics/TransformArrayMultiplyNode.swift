//
//  TransformArrayMultiplyNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class TransformArrayMultiplyNode: Node
{
    public override class var name: String { "Transform Array Multiply" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Multiplies two arrays of Transforms per element: A × B, which applies B first, then A. Use it to stack motions, such as a piece riding its parent's motion. Output length matches the longer input; the shorter input pads with identity." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        super.registerPorts(context: context) +
        [
            ("inputA", NodePort<ContiguousArray<simd_float4x4>>(name: "A", kind: .Inlet, description: "Applied second, on top of B")),
            ("inputB", NodePort<ContiguousArray<simd_float4x4>>(name: "B", kind: .Inlet, description: "Applied first")),
            ("outputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Outlet, description: "A × B per element")),
        ]
    }

    public var inputA: NodePort<ContiguousArray<simd_float4x4>> { port(named: "inputA") }
    public var inputB: NodePort<ContiguousArray<simd_float4x4>> { port(named: "inputB") }
    public var outputTransforms: NodePort<ContiguousArray<simd_float4x4>> { port(named: "outputTransforms") }

    /// `a[i] × b[i]`, as long as the longer array; a missing element is identity.
    public static func multiplied(_ a: ContiguousArray<simd_float4x4>, _ b: ContiguousArray<simd_float4x4>) -> ContiguousArray<simd_float4x4>
    {
        let count = max(a.count, b.count)
        var output = ContiguousArray<simd_float4x4>()
        output.reserveCapacity(count)
        for index in 0..<count
        {
            let first = index < a.count ? a[index] : matrix_identity_float4x4
            let second = index < b.count ? b[index] : matrix_identity_float4x4
            output.append(simd_mul(first, second))
        }
        return output
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard self.inputA.valueDidChange || self.inputB.valueDidChange else { return }
        self.outputTransforms.send(Self.multiplied(self.inputA.value ?? [], self.inputB.value ?? []))
    }
}
