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
    public override class var name: String { "Orientation - Face Outward" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "For each input position, produces a quaternion whose local +Z axis points from the origin outward through the position, with local +Y aligned to the Up reference. Positions at the origin map to identity. When a position's outward direction becomes parallel to Up, the node falls back to a nearby world axis, which can cause an abrupt change in the resulting roll; supply an alternate Up to move that discontinuity elsewhere." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet, description: "Per-element position (XYZ)")),
            ("inputUp", ParameterPort(parameter: Float3Parameter("Up", simd_float3(0, 0, 1), .inputfield, "Reference up axis. Local +Y of each orientation aligns with this where possible; when a position's outward direction is parallel to Up the node falls back to a nearby world axis."))),
            ("outputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Per-element quaternion orientation (X, Y, Z, W) facing away from origin")),
        ]
    }

    public var inputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "inputPositions") }
    public var inputUp: ParameterPort<simd_float3> { port(named: "inputUp") }
    public var outputOrientations: NodePort<ContiguousArray<simd_float4>> { port(named: "outputOrientations") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPositions.valueDidChange || self.inputUp.valueDidChange else { return }
        guard let positions = self.inputPositions.value else { return }
        let up = self.inputUp.value ?? simd_float3(0, 0, 1)

        var output = ContiguousArray<simd_float4>()
        output.reserveCapacity(positions.count)
        for p in positions {
            output.append(quatLookingAlong(p, up: up).vector)
        }
        self.outputOrientations.send(output)
    }
}

public class LookAtNode : Node
{
    public override class var name: String { "Orientation - Look At" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "For each input position, produces a quaternion whose local +Z axis points toward the Target, with local +Y aligned to the Up reference. Positions coincident with Target map to identity. When a look direction becomes parallel to Up, the node falls back to a nearby world axis, which can cause an abrupt change in the resulting roll; supply an alternate Up to move that discontinuity elsewhere." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet, description: "Per-element position (XYZ)")),
            ("inputTarget", ParameterPort(parameter: Float3Parameter("Target", simd_float3(0, 0, 0), .inputfield, "World-space target each orientation should face"))),
            ("inputUp", ParameterPort(parameter: Float3Parameter("Up", simd_float3(0, 0, 1), .inputfield, "Reference up axis. Local +Y of each orientation aligns with this where possible; when a look direction is parallel to Up the node falls back to a nearby world axis."))),
            ("outputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Per-element quaternion orientation (X, Y, Z, W) facing the Target")),
        ]
    }

    public var inputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "inputPositions") }
    public var inputTarget: ParameterPort<simd_float3> { port(named: "inputTarget") }
    public var inputUp: ParameterPort<simd_float3> { port(named: "inputUp") }
    public var outputOrientations: NodePort<ContiguousArray<simd_float4>> { port(named: "outputOrientations") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPositions.valueDidChange
            || self.inputTarget.valueDidChange
            || self.inputUp.valueDidChange
        else { return }
        guard let positions = self.inputPositions.value else { return }
        let target = self.inputTarget.value ?? simd_float3(0, 0, 0)
        let up = self.inputUp.value ?? simd_float3(0, 0, 1)

        var output = ContiguousArray<simd_float4>()
        output.reserveCapacity(positions.count)
        for p in positions {
            output.append(quatLookingAlong(target - p, up: up).vector)
        }
        self.outputOrientations.send(output)
    }
}

/// Quaternion orientation whose local +Z points along `direction` and whose
/// local +Y is aligned with `up` where possible. When `direction` is parallel
/// to `up`, falls back to whichever world axis is most perpendicular to
/// `direction` — this may cause an abrupt roll change at the fallback boundary.
/// Returns identity for zero-length `direction`.
@inline(__always)
fileprivate func quatLookingAlong(_ direction: simd_float3, up: simd_float3) -> simd_quatf {
    let eps: Float = 1e-4
    let lenSq = simd_length_squared(direction)
    guard lenSq > eps else { return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
    let forward = direction / sqrt(lenSq)

    // Normalise the supplied up, falling back if the user supplied zero.
    let upLenSq = simd_length_squared(up)
    var upRef: simd_float3 = upLenSq > eps ? (up / sqrt(upLenSq)) : simd_float3(0, 0, 1)

    // If forward is parallel (or anti-parallel) to the up reference, swap in
    // whichever world axis is most perpendicular to forward.
    if abs(simd_dot(upRef, forward)) > 1 - eps {
        let candidates: [simd_float3] = [
            simd_float3(1, 0, 0),
            simd_float3(0, 1, 0),
            simd_float3(0, 0, 1),
        ]
        upRef = candidates.min(by: { abs(simd_dot($0, forward)) < abs(simd_dot($1, forward)) })!
    }

    let right = simd_normalize(simd_cross(upRef, forward))
    let newUp = simd_cross(forward, right)
    // simd_float3x3 initialiser takes columns — local +X, +Y, +Z in world.
    let m = simd_float3x3(right, newUp, forward)
    return simd_quatf(m).normalized
}
