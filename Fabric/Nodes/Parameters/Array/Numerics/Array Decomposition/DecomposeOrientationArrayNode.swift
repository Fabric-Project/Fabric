//
//  DecomposeOrientationArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class DecomposeOrientationArrayNode: StrategyNode
{
    public override class var name: String { "Orientation Array Decompose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits an array of Orientation quaternions into per-element Euler angles or Axis + Angle, depending on strategy." }

    public override class var strategies: [String] { ["To Euler", "To Axis Angle"] }

    private static let allDynamicNames: Set<String> = [
        "inputOrientations",
        "outputX", "outputY", "outputZ",
        "outputAxes", "outputAngles",
    ]

    public override func rebuildPorts(forStrategy strategy: String)
    {
        let wanted: [(name: String, port: Port)]
        switch strategy
        {
        case "To Euler":
            wanted =
            [
                ("inputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Inlet, description: "Per-element quaternion orientation (X, Y, Z, W)")),
                ("outputX", NodePort<ContiguousArray<Float>>(name: "X (Pitch)", kind: .Outlet, description: "Per-element rotation around the X axis in degrees")),
                ("outputY", NodePort<ContiguousArray<Float>>(name: "Y (Yaw)", kind: .Outlet, description: "Per-element rotation around the Y axis in degrees")),
                ("outputZ", NodePort<ContiguousArray<Float>>(name: "Z (Roll)", kind: .Outlet, description: "Per-element rotation around the Z axis in degrees")),
            ]

        case "To Axis Angle":
            wanted =
            [
                ("inputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Inlet, description: "Per-element quaternion orientation (X, Y, Z, W)")),
                ("outputAxes", NodePort<ContiguousArray<simd_float3>>(name: "Axes", kind: .Outlet, description: "Per-element normalized rotation axis")),
                ("outputAngles", NodePort<ContiguousArray<Float>>(name: "Angles", kind: .Outlet, description: "Per-element rotation angle in degrees")),
            ]

        default:
            wanted = []
        }

        let wantedNames = Set(wanted.map(\.name))
        for name in Self.allDynamicNames.subtracting(wantedNames)
        {
            if let p = findPort(named: name) { removePort(p) }
        }
        for (name, p) in wanted where findPort(named: name) == nil
        {
            addDynamicPort(p, name: name)
        }
    }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let inputOrientations: NodePort<ContiguousArray<simd_float4>> = findPort(named: "inputOrientations"),
              inputOrientations.valueDidChange
        else { return }

        let orientations = inputOrientations.value ?? ContiguousArray<simd_float4>()
        let quats = orientations.map { simd_quatf(safeVector: $0) }

        switch self.strategy
        {
        case "To Euler":
            guard let outputX: NodePort<ContiguousArray<Float>> = findPort(named: "outputX"),
                  let outputY: NodePort<ContiguousArray<Float>> = findPort(named: "outputY"),
                  let outputZ: NodePort<ContiguousArray<Float>> = findPort(named: "outputZ")
            else { return }

            var xs = ContiguousArray<Float>(); xs.reserveCapacity(quats.count)
            var ys = ContiguousArray<Float>(); ys.reserveCapacity(quats.count)
            var zs = ContiguousArray<Float>(); zs.reserveCapacity(quats.count)
            for q in quats {
                let euler = q.eulerAnglesDegreesXYZ
                xs.append(euler.x)
                ys.append(euler.y)
                zs.append(euler.z)
            }
            outputX.send(xs)
            outputY.send(ys)
            outputZ.send(zs)

        case "To Axis Angle":
            guard let outputAxes: NodePort<ContiguousArray<simd_float3>> = findPort(named: "outputAxes"),
                  let outputAngles: NodePort<ContiguousArray<Float>> = findPort(named: "outputAngles")
            else { return }

            var axes = ContiguousArray<simd_float3>(); axes.reserveCapacity(quats.count)
            var angles = ContiguousArray<Float>(); angles.reserveCapacity(quats.count)
            for q in quats {
                let (axis, angleDegrees) = q.axisAngleDegrees
                axes.append(axis)
                angles.append(angleDegrees)
            }
            outputAxes.send(axes)
            outputAngles.send(angles)

        default:
            break
        }
    }
}
