//
//  ComposeTransformArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class ComposeTransformArrayNode: StrategyNode
{
    public override class var name: String { "Transform Array Compose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Builds an array of Transforms via one of several strategies: per-element Positions/Orientations/Scales (TRS), or directly from four per-element column arrays. Inputs are zipped per element; output length matches the longest, shorter inputs pad with their last element." }

    public override class var strategyOptions: [any NodeStrategyOption] { TransformCompositionMode.allCases }

    private static let allDynamicNames: Set<String> = [
        "inputPositions", "inputOrientations", "inputScales",
        "inputColumn0s", "inputColumn1s", "inputColumn2s", "inputColumn3s",
        "outputTransforms",
    ]

    public override func rebuildPorts(forStrategy strategy: String)
    {
        let wanted: [(name: String, port: Port)]
        switch strategy
        {
        case "TRS":
            wanted =
            [
                ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet, description: "Per-element position (XYZ)")),
                ("inputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Inlet, description: "Per-element quaternion orientation (X, Y, Z, W)")),
                ("inputScales", NodePort<ContiguousArray<simd_float3>>(name: "Scales", kind: .Inlet, description: "Per-element scale (XYZ)")),
                ("outputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Outlet, description: "Array of per-element model matrices (T*R*S)")),
            ]

        case "Columns":
            wanted =
            [
                ("inputColumn0s", NodePort<ContiguousArray<simd_float4>>(name: "Column 0s", kind: .Inlet, description: "Per-element first column of the matrix")),
                ("inputColumn1s", NodePort<ContiguousArray<simd_float4>>(name: "Column 1s", kind: .Inlet, description: "Per-element second column of the matrix")),
                ("inputColumn2s", NodePort<ContiguousArray<simd_float4>>(name: "Column 2s", kind: .Inlet, description: "Per-element third column of the matrix")),
                ("inputColumn3s", NodePort<ContiguousArray<simd_float4>>(name: "Column 3s", kind: .Inlet, description: "Per-element fourth column of the matrix (translation, when W=1)")),
                ("outputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Outlet, description: "Array of per-element matrices built from their four columns")),
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
        guard let outputTransforms: NodePort<ContiguousArray<simd_float4x4>> = findPort(named: "outputTransforms") else { return }

        switch self.strategy
        {
        case "TRS":
            guard let inputPositions: NodePort<ContiguousArray<simd_float3>> = findPort(named: "inputPositions"),
                  let inputOrientations: NodePort<ContiguousArray<simd_float4>> = findPort(named: "inputOrientations"),
                  let inputScales: NodePort<ContiguousArray<simd_float3>> = findPort(named: "inputScales")
            else { return }
            guard inputPositions.valueDidChange || inputOrientations.valueDidChange || inputScales.valueDidChange else { return }

            let posIn = inputPositions.value
            let orIn = inputOrientations.value
            let scIn = inputScales.value

            let count = [posIn?.count ?? 0, orIn?.count ?? 0, scIn?.count ?? 0].max() ?? 0
            guard count > 0 else {
                outputTransforms.send(ContiguousArray<simd_float4x4>())
                return
            }

            let positions    = (posIn ?? []).paddedToLast(count: count, fallback: simd_float3(0, 0, 0))
            let orientations = (orIn ?? []).paddedToLast(count: count, fallback: simd_float4(0, 0, 0, 1))
            let scales       = (scIn ?? []).paddedToLast(count: count, fallback: simd_float3(1, 1, 1))

            var output = ContiguousArray<simd_float4x4>(repeating: matrix_identity_float4x4, count: count)
            // simd_quatf(safeVector:) is folded into the parallel loop — saves
            // the serial pre-pass and intermediate [simd_quatf] allocation.
            let concurrentThreshold = 128
            if count >= concurrentThreshold {
                output.withUnsafeMutableBufferPointer { buf in
                    DispatchQueue.concurrentPerform(iterations: count) { i in
                        let s = scales[i]
                        var m = matrix_float4x4(simd_quatf(safeVector: orientations[i]))
                        m.columns.0 *= s.x
                        m.columns.1 *= s.y
                        m.columns.2 *= s.z
                        m.columns.3 = simd_float4(positions[i], 1)
                        buf[i] = m
                    }
                }
            } else {
                for i in 0..<count {
                    let s = scales[i]
                    var m = matrix_float4x4(simd_quatf(safeVector: orientations[i]))
                    m.columns.0 *= s.x
                    m.columns.1 *= s.y
                    m.columns.2 *= s.z
                    m.columns.3 = simd_float4(positions[i], 1)
                    output[i] = m
                }
            }
            outputTransforms.send(output)

        case "Columns":
            guard let inputColumn0s: NodePort<ContiguousArray<simd_float4>> = findPort(named: "inputColumn0s"),
                  let inputColumn1s: NodePort<ContiguousArray<simd_float4>> = findPort(named: "inputColumn1s"),
                  let inputColumn2s: NodePort<ContiguousArray<simd_float4>> = findPort(named: "inputColumn2s"),
                  let inputColumn3s: NodePort<ContiguousArray<simd_float4>> = findPort(named: "inputColumn3s")
            else { return }
            guard inputColumn0s.valueDidChange || inputColumn1s.valueDidChange
                || inputColumn2s.valueDidChange || inputColumn3s.valueDidChange
            else { return }

            let c0In = inputColumn0s.value
            let c1In = inputColumn1s.value
            let c2In = inputColumn2s.value
            let c3In = inputColumn3s.value

            let count = [c0In?.count ?? 0, c1In?.count ?? 0, c2In?.count ?? 0, c3In?.count ?? 0].max() ?? 0
            guard count > 0 else {
                outputTransforms.send(ContiguousArray<simd_float4x4>())
                return
            }

            let c0s = (c0In ?? []).paddedToLast(count: count, fallback: simd_float4(1, 0, 0, 0))
            let c1s = (c1In ?? []).paddedToLast(count: count, fallback: simd_float4(0, 1, 0, 0))
            let c2s = (c2In ?? []).paddedToLast(count: count, fallback: simd_float4(0, 0, 1, 0))
            let c3s = (c3In ?? []).paddedToLast(count: count, fallback: simd_float4(0, 0, 0, 1))

            var output = ContiguousArray<simd_float4x4>(repeating: matrix_identity_float4x4, count: count)
            let concurrentThreshold = 128
            if count >= concurrentThreshold {
                output.withUnsafeMutableBufferPointer { buf in
                    DispatchQueue.concurrentPerform(iterations: count) { i in
                        buf[i] = simd_float4x4(c0s[i], c1s[i], c2s[i], c3s[i])
                    }
                }
            } else {
                for i in 0..<count {
                    output[i] = simd_float4x4(c0s[i], c1s[i], c2s[i], c3s[i])
                }
            }
            outputTransforms.send(output)

        default:
            break
        }
    }
}
