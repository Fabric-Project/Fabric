//
//  FaceOutwardNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class FaceOutwardNode : Node
{
    public override class var name: String { "Face Outward" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "For each input position, produces a quaternion whose local +Z axis points from the origin out through the position. Positions at the origin map to identity." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet, description: "Per-element position (XYZ)")),
            ("outputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Per-element quaternion orientation (X, Y, Z, W) facing away from origin")),
        ]
    }

    public var inputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "inputPositions") }
    public var outputOrientations: NodePort<ContiguousArray<simd_float4>> { port(named: "outputOrientations") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPositions.valueDidChange else { return }
        guard let positions = self.inputPositions.value else { return }

        var output = ContiguousArray<simd_float4>()
        output.reserveCapacity(positions.count)
        for p in positions {
            output.append(quatLookingAlong(p).vector)
        }
        self.outputOrientations.send(output)
    }
}

public class LookAtNode : Node
{
    public override class var name: String { "Look At" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "For each input position, produces a quaternion whose local +Z axis points toward the Target. Positions coincident with Target map to identity." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet, description: "Per-element position (XYZ)")),
            ("inputTarget", ParameterPort(parameter: Float3Parameter("Target", simd_float3(0, 0, 0), .inputfield, "World-space target each orientation should face"))),
            ("outputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Per-element quaternion orientation (X, Y, Z, W) facing the Target")),
        ]
    }

    public var inputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "inputPositions") }
    public var inputTarget: ParameterPort<simd_float3> { port(named: "inputTarget") }
    public var outputOrientations: NodePort<ContiguousArray<simd_float4>> { port(named: "outputOrientations") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPositions.valueDidChange || self.inputTarget.valueDidChange else { return }
        guard let positions = self.inputPositions.value else { return }
        let target = self.inputTarget.value ?? simd_float3(0, 0, 0)

        var output = ContiguousArray<simd_float4>()
        output.reserveCapacity(positions.count)
        for p in positions {
            output.append(quatLookingAlong(target - p).vector)
        }
        self.outputOrientations.send(output)
    }
}

/// Quaternion that rotates local +Z to point along `direction`.
/// Returns identity for zero-length input; handles the 180° flip case explicitly.
@inline(__always)
fileprivate func quatLookingAlong(_ direction: simd_float3) -> simd_quatf {
    let eps: Float = 1e-6
    let lenSq = simd_length_squared(direction)
    guard lenSq > eps else { return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
    let dir = direction / sqrt(lenSq)
    let from = simd_float3(0, 0, 1)
    let d = simd_dot(from, dir)
    if d > 1 - eps { return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
    if d < -1 + eps {
        return simd_quatf(angle: .pi, axis: simd_float3(0, 1, 0))
    }
    return simd_quatf(from: from, to: dir).normalized
}
