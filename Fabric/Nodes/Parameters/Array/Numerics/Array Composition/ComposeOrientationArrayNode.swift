//
//  ComposeOrientationArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class ComposeOrientationArrayNode: StrategyNode
{
    public override class var name: String { "Orientation Array Compose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Builds an array of Orientation quaternions via one of several strategies: Euler angles, Axis + Angle, or aiming at a Target. Inputs are zipped per element; output length matches the longest, shorter inputs pad with their last element." }

    public override class var strategyOptions: [any NodeStrategyOption] { OrientationCompositionMode.allCases }

    private static let allDynamicNames: Set<String> = [
        "inputEulerAngles",
        "inputAxes", "inputAngles",
        "inputPositions", "inputTargets", "inputUpOrientations", "inputAimOffsets",
        "outputOrientations",
    ]

    public override func rebuildPorts(forStrategy strategy: String)
    {
        let wanted: [(name: String, port: Port)]
        switch strategy
        {
        case "Euler":
            wanted =
            [
                ("inputEulerAngles", NodePort<ContiguousArray<simd_float3>>(name: "Euler Angles", kind: .Inlet, description: "Per-element Euler angles in degrees (X=pitch, Y=yaw, Z=roll)")),
                ("outputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Per-element quaternion orientation (X, Y, Z, W)")),
            ]

        case "Axis Angle":
            wanted =
            [
                ("inputAxes", NodePort<ContiguousArray<simd_float3>>(name: "Axes", kind: .Inlet, description: "Per-element rotation axis (will be normalized)")),
                ("inputAngles", NodePort<ContiguousArray<Float>>(name: "Angles", kind: .Inlet, description: "Per-element rotation angle in degrees")),
                ("outputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Per-element quaternion orientation (X, Y, Z, W)")),
            ]

        case "Target":
            wanted =
            [
                ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet, description: "Per-element viewpoint position (XYZ)")),
                ("inputTargets", NodePort<ContiguousArray<simd_float3>>(name: "Targets", kind: .Inlet, description: "Per-element world-space target to face (XYZ)")),
                ("inputUpOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Up Orientations", kind: .Inlet, description: "Per-element roll reference; local +Z is the up direction (identity gives world +Z). Quaternion (X, Y, Z, W)")),
                ("inputAimOffsets", NodePort<ContiguousArray<simd_float4>>(name: "Aim Offsets", kind: .Inlet, description: "Per-element rotation in the look frame after aiming (identity looks at, 180° looks away). Quaternion (X, Y, Z, W)")),
                ("outputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Per-element quaternion orientation (X, Y, Z, W)")),
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
        guard let outputOrientations: NodePort<ContiguousArray<simd_float4>> = findPort(named: "outputOrientations") else { return }

        switch self.strategy
        {
        case "Euler":
            guard let inputEulerAngles: NodePort<ContiguousArray<simd_float3>> = findPort(named: "inputEulerAngles") else { return }
            guard inputEulerAngles.valueDidChange else { return }
            guard let eulerAngles = inputEulerAngles.value else {
                outputOrientations.send(ContiguousArray<simd_float4>())
                return
            }

            let count = eulerAngles.count
            var output = ContiguousArray<simd_float4>(repeating: simd_float4(0, 0, 0, 1), count: count)
            let concurrentThreshold = 128
            if count >= concurrentThreshold {
                output.withUnsafeMutableBufferPointer { buf in
                    DispatchQueue.concurrentPerform(iterations: count) { i in
                        buf[i] = simd_quatf(eulerAnglesDegrees: eulerAngles[i]).vector
                    }
                }
            } else {
                for i in 0..<count {
                    output[i] = simd_quatf(eulerAnglesDegrees: eulerAngles[i]).vector
                }
            }
            outputOrientations.send(output)

        case "Axis Angle":
            guard let inputAxes: NodePort<ContiguousArray<simd_float3>> = findPort(named: "inputAxes"),
                  let inputAngles: NodePort<ContiguousArray<Float>> = findPort(named: "inputAngles")
            else { return }
            guard inputAxes.valueDidChange || inputAngles.valueDidChange else { return }

            let axesIn = inputAxes.value
            let anglesIn = inputAngles.value
            let count = [axesIn?.count ?? 0, anglesIn?.count ?? 0].max() ?? 0
            guard count > 0 else {
                outputOrientations.send(ContiguousArray<simd_float4>())
                return
            }

            let axes = (axesIn ?? []).paddedToLast(count: count, fallback: simd_float3(0, 1, 0))
            let angles = (anglesIn ?? []).paddedToLast(count: count, fallback: 0)

            var output = ContiguousArray<simd_float4>(repeating: simd_float4(0, 0, 0, 1), count: count)
            let concurrentThreshold = 128
            if count >= concurrentThreshold {
                output.withUnsafeMutableBufferPointer { buf in
                    DispatchQueue.concurrentPerform(iterations: count) { i in
                        buf[i] = simd_quatf(axis: axes[i], angleDegrees: angles[i]).vector
                    }
                }
            } else {
                for i in 0..<count {
                    output[i] = simd_quatf(axis: axes[i], angleDegrees: angles[i]).vector
                }
            }
            outputOrientations.send(output)

        case "Target":
            guard let inputPositions: NodePort<ContiguousArray<simd_float3>> = findPort(named: "inputPositions"),
                  let inputTargets: NodePort<ContiguousArray<simd_float3>> = findPort(named: "inputTargets"),
                  let inputUpOrientations: NodePort<ContiguousArray<simd_float4>> = findPort(named: "inputUpOrientations"),
                  let inputAimOffsets: NodePort<ContiguousArray<simd_float4>> = findPort(named: "inputAimOffsets")
            else { return }
            guard inputPositions.valueDidChange || inputTargets.valueDidChange
                || inputUpOrientations.valueDidChange || inputAimOffsets.valueDidChange
            else { return }

            let posIn = inputPositions.value
            let tgtIn = inputTargets.value
            let upIn = inputUpOrientations.value
            let aimIn = inputAimOffsets.value
            let count = [posIn?.count ?? 0, tgtIn?.count ?? 0, upIn?.count ?? 0, aimIn?.count ?? 0].max() ?? 0
            guard count > 0 else {
                outputOrientations.send(ContiguousArray<simd_float4>())
                return
            }

            let positions = (posIn ?? []).paddedToLast(count: count, fallback: simd_float3(0, 0, 0))
            let targets = (tgtIn ?? []).paddedToLast(count: count, fallback: simd_float3(0, 0, 0))
            let ups = (upIn ?? []).paddedToLast(count: count, fallback: simd_float4(0, 0, 0, 1))
            let aims = (aimIn ?? []).paddedToLast(count: count, fallback: simd_float4(0, 0, 0, 1))

            var output = ContiguousArray<simd_float4>(repeating: simd_float4(0, 0, 0, 1), count: count)
            let concurrentThreshold = 128
            if count >= concurrentThreshold {
                output.withUnsafeMutableBufferPointer { buf in
                    DispatchQueue.concurrentPerform(iterations: count) { i in
                        let up = simd_quatf.upDirection(from: ups[i])
                        let look = simd_quatf(lookingAlong: targets[i] - positions[i], up: up)
                        buf[i] = (look * simd_quatf(safeVector: aims[i])).vector
                    }
                }
            } else {
                for i in 0..<count {
                    let up = simd_quatf.upDirection(from: ups[i])
                    let look = simd_quatf(lookingAlong: targets[i] - positions[i], up: up)
                    output[i] = (look * simd_quatf(safeVector: aims[i])).vector
                }
            }
            outputOrientations.send(output)

        default:
            break
        }
    }
}
