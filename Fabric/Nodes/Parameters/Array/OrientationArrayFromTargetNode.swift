//
//  OrientationArrayFromTargetNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class OrientationArrayFromTargetNode : Node
{
    public override class var name: String { "Orientation Array From Target" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "For each element, produces a quaternion whose local +Z axis points from Position toward Target, with roll resolved against Up Orientation, then post-multiplied by Aim Offset. Inputs are zipped per element; output length matches the longest, shorter inputs pad with their last element (so a single-element array broadcasts as a constant). Up Orientation's local +Z is the up reference (identity gives world +Z), matching the point generators. Aim Offset re-aims in the look frame: identity looks at the Target, 180° looks away. Positions coincident with their Target map to identity." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet, description: "Per-element viewpoint position (XYZ)")),
            ("inputTargets", NodePort<ContiguousArray<simd_float3>>(name: "Targets", kind: .Inlet, description: "Per-element world-space target to face (XYZ)")),
            ("inputUpOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Up Orientations", kind: .Inlet, description: "Per-element roll reference; local +Z is the up direction (identity gives world +Z). Quaternion (X, Y, Z, W)")),
            ("inputAimOffsets", NodePort<ContiguousArray<simd_float4>>(name: "Aim Offsets", kind: .Inlet, description: "Per-element rotation in the look frame after aiming (identity looks at, 180° looks away). Quaternion (X, Y, Z, W)")),
            ("outputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Per-element quaternion orientation (X, Y, Z, W)")),
        ]
    }

    public var inputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "inputPositions") }
    public var inputTargets: NodePort<ContiguousArray<simd_float3>> { port(named: "inputTargets") }
    public var inputUpOrientations: NodePort<ContiguousArray<simd_float4>> { port(named: "inputUpOrientations") }
    public var inputAimOffsets: NodePort<ContiguousArray<simd_float4>> { port(named: "inputAimOffsets") }
    public var outputOrientations: NodePort<ContiguousArray<simd_float4>> { port(named: "outputOrientations") }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPositions.valueDidChange
            || self.inputTargets.valueDidChange
            || self.inputUpOrientations.valueDidChange
            || self.inputAimOffsets.valueDidChange
        else { return }

        let posIn = self.inputPositions.value
        let tgtIn = self.inputTargets.value
        let upIn = self.inputUpOrientations.value
        let aimIn = self.inputAimOffsets.value

        let count = [posIn?.count ?? 0, tgtIn?.count ?? 0, upIn?.count ?? 0, aimIn?.count ?? 0].max() ?? 0
        guard count > 0 else {
            self.outputOrientations.send(ContiguousArray<simd_float4>())
            return
        }

        // Zip per element; shorter inputs broadcast their last element.
        let positions = (posIn ?? []).paddedToLast(count: count, fallback: simd_float3(0, 0, 0))
        let targets = (tgtIn ?? []).paddedToLast(count: count, fallback: simd_float3(0, 0, 0))
        let ups = (upIn ?? []).paddedToLast(count: count, fallback: simd_float4(0, 0, 0, 1))
        let aims = (aimIn ?? []).paddedToLast(count: count, fallback: simd_float4(0, 0, 0, 1))

        var output = ContiguousArray<simd_float4>()
        output.reserveCapacity(count)
        for i in 0..<count {
            let up = simd_quatf.upDirection(from: ups[i])
            let look = simd_quatf(lookingAlong: targets[i] - positions[i], up: up)
            output.append((look * simd_quatf(safeVector: aims[i])).vector)
        }
        self.outputOrientations.send(output)
    }
}
