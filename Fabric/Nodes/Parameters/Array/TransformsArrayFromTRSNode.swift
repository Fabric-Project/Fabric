//
//  TransformsArrayFromTRSNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class TransformsArrayFromTRSNode : Node
{
    public override class var name: String { "Transforms Array From TRS" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Zips per-element Positions, Orientations and Scales arrays into a Transform array via T*R*S. Output length matches the longest input; shorter inputs pad with their last element (so a single-element array broadcasts as a constant for that component). Unconnected inputs default: position (0,0,0), orientation identity, scale (1,1,1)." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet, description: "Per-element position (XYZ)")),
            ("inputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Inlet, description: "Per-element quaternion orientation (X, Y, Z, W)")),
            ("inputScales", NodePort<ContiguousArray<simd_float3>>(name: "Scales", kind: .Inlet, description: "Per-element scale (XYZ)")),
            ("outputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Outlet, description: "Array of per-element model matrices (T*R*S)")),
        ]
    }

    public var inputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "inputPositions") }
    public var inputOrientations: NodePort<ContiguousArray<simd_float4>> { port(named: "inputOrientations") }
    public var inputScales: NodePort<ContiguousArray<simd_float3>> { port(named: "inputScales") }
    public var outputTransforms: NodePort<ContiguousArray<simd_float4x4>> { port(named: "outputTransforms") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPositions.valueDidChange
            || self.inputOrientations.valueDidChange
            || self.inputScales.valueDidChange
        else { return }

        let posIn = self.inputPositions.value
        let orIn = self.inputOrientations.value
        let scIn = self.inputScales.value

        let count = [posIn?.count ?? 0, orIn?.count ?? 0, scIn?.count ?? 0].max() ?? 0
        guard count > 0 else {
            self.outputTransforms.send(ContiguousArray<simd_float4x4>())
            return
        }

        let positions = padLast(posIn, count: count, fallback: simd_float3(0, 0, 0))
        let orientationQuats = padLast(orIn, count: count, fallback: simd_float4(0, 0, 0, 1))
            .map { simd_quatf(vector: $0).normalized }
        let scales = padLast(scIn, count: count, fallback: simd_float3(1, 1, 1))

        var output = ContiguousArray<simd_float4x4>()
        output.reserveCapacity(count)
        for i in 0..<count {
            let t = translationMatrix3f(positions[i])
            let r = matrix_float4x4(orientationQuats[i])
            let s = scaleMatrix3f(scales[i])
            output.append(simd_mul(simd_mul(t, r), s))
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
