//
//  LookAtNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class LookAtNode : Node
{
    public override class var name: String { "Orientation - Look At" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "For each input position, produces a quaternion whose local +Z axis points toward the Target, with roll resolved against Up Orientation, then post-multiplied by Aim Offset. Up Orientation is a quaternion in the same format as the point generators' Up Orientation: its local +Z is used as the up reference (identity gives world +Z), so feeding a generator's Up Orientation here makes the roll track the same tilt. Aim Offset re-aims the result in its local frame: identity looks straight at the Target, a 180° rotation looks away (e.g. facing outward from the Target). Positions coincident with the Target map to identity. When the look direction is parallel to the up reference the node falls back to a nearby world axis, which can cause an abrupt roll change." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet, description: "Per-element position (XYZ)")),
            ("inputTarget", ParameterPort(parameter: Float3Parameter("Target", simd_float3(0, 0, 0), .inputfield, "World-space target each orientation should face"))),
            ("inputUp", ParameterPort(parameter: Float4Parameter("Up Orientation", simd_float4(0, 0, 0, 1), .inputfield, "Roll reference, in the same Up Orientation (quaternion) format as the point generators. Its local +Z is the up direction (identity gives world +Z); feed a generator's Up Orientation here so roll tracks the same tilt. Quaternion (X, Y, Z, W)."))),
            ("inputOrientation", ParameterPort(parameter: Float4Parameter("Aim Offset", simd_float4(0, 0, 0, 1), .inputfield, "Rotation applied in the look frame after aiming at the Target. Identity looks at; a 180° rotation looks away. Quaternion (X, Y, Z, W)."))),
            ("outputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Per-element quaternion orientation (X, Y, Z, W)")),
        ]
    }

    public var inputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "inputPositions") }
    public var inputTarget: ParameterPort<simd_float3> { port(named: "inputTarget") }
    public var inputUp: ParameterPort<simd_float4> { port(named: "inputUp") }
    public var inputOrientation: ParameterPort<simd_float4> { port(named: "inputOrientation") }
    public var outputOrientations: NodePort<ContiguousArray<simd_float4>> { port(named: "outputOrientations") }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPositions.valueDidChange
            || self.inputTarget.valueDidChange
            || self.inputUp.valueDidChange
            || self.inputOrientation.valueDidChange
        else { return }
        guard let positions = self.inputPositions.value else {
            self.outputOrientations.send(ContiguousArray<simd_float4>())
            return
        }
        let target = self.inputTarget.value ?? simd_float3(0, 0, 0)

        // Up reference is an Orientation (quaternion), same format as the point
        // generators. Its local +Z is the up direction (identity -> world +Z),
        // so feeding a generator's Orientation makes roll track the same tilt.
        let up = simd_quatf(safeVector: self.inputUp.value ?? simd_float4(0, 0, 0, 1)).act(simd_float3(0, 0, 1))

        // Local post-rotation applied after the look-at frame is built.
        let offset = simd_quatf(safeVector: self.inputOrientation.value ?? simd_float4(0, 0, 0, 1))

        var output = ContiguousArray<simd_float4>()
        output.reserveCapacity(positions.count)
        for p in positions {
            let look = quatLookingAlong(target - p, up: up)
            output.append((look * offset).vector)
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
    // Reject zero-length, NaN and Inf directions (Inf would pass a bare > eps
    // and yield Inf/Inf = NaN below). The tiny threshold keeps the
    // "coincident with target -> identity" dead zone negligible.
    guard lenSq.isFinite, lenSq > 1e-12 else { return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
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
