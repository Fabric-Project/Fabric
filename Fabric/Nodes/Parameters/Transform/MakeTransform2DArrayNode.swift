//
//  MakeTransform2DArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class MakeTransform2DArrayNode : Node
{
    override public class var name: String { "Make Transform2D Array" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Zips parallel arrays of pan, scale, rotation and pivot into an array of 4x4 2D transforms. Output length matches the longest input; shorter inputs pad with their last element. Defaults per-element: pan (0, 0), scale (1, 1), rotation 0, pivot (0.5, 0.5)." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPans", NodePort<ContiguousArray<simd_float2>>(name: "Pans", kind: .Inlet, description: "Per-element translation")),
            ("inputScales", NodePort<ContiguousArray<simd_float2>>(name: "Scales", kind: .Inlet, description: "Per-element scale factor")),
            ("inputRotations", NodePort<ContiguousArray<Float>>(name: "Rotations (degrees)", kind: .Inlet, description: "Per-element rotation in degrees around the corresponding pivot")),
            ("inputPivots", NodePort<ContiguousArray<simd_float2>>(name: "Pivots", kind: .Inlet, description: "Per-element fixed point around which scale and rotation are applied")),
            ("outputTransform2Ds", NodePort<ContiguousArray<simd_float4x4>>(name: "Transform2Ds", kind: .Outlet, description: "Array of 4x4 2D transforms")),
        ]
    }

    public var inputPans: NodePort<ContiguousArray<simd_float2>> { port(named: "inputPans") }
    public var inputScales: NodePort<ContiguousArray<simd_float2>> { port(named: "inputScales") }
    public var inputRotations: NodePort<ContiguousArray<Float>> { port(named: "inputRotations") }
    public var inputPivots: NodePort<ContiguousArray<simd_float2>> { port(named: "inputPivots") }
    public var outputTransform2Ds: NodePort<ContiguousArray<simd_float4x4>> { port(named: "outputTransform2Ds") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPans.valueDidChange
            || self.inputScales.valueDidChange
            || self.inputRotations.valueDidChange
            || self.inputPivots.valueDidChange
        else { return }

        let pansIn = self.inputPans.value
        let scalesIn = self.inputScales.value
        let rotsIn = self.inputRotations.value
        let pivotsIn = self.inputPivots.value

        let count = [
            pansIn?.count ?? 0,
            scalesIn?.count ?? 0,
            rotsIn?.count ?? 0,
            pivotsIn?.count ?? 0,
        ].max() ?? 0
        guard count > 0 else {
            self.outputTransform2Ds.send(ContiguousArray<simd_float4x4>())
            return
        }

        let pans = padLast(pansIn, count: count, fallback: simd_float2(0, 0))
        let scales = padLast(scalesIn, count: count, fallback: simd_float2(1, 1))
        let rots = padLast(rotsIn, count: count, fallback: Float(0))
        let pivots = padLast(pivotsIn, count: count, fallback: simd_float2(0.5, 0.5))

        var output = ContiguousArray<simd_float4x4>()
        output.reserveCapacity(count)
        for i in 0..<count {
            output.append(
                MakeTransform2DNode.transform2D(
                    pan: pans[i],
                    scale: scales[i],
                    rotationDegrees: rots[i],
                    pivot: pivots[i]
                )
            )
        }
        self.outputTransform2Ds.send(output)
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
