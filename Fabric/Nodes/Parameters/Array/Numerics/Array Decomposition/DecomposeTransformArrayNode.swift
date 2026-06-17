//
//  DecomposeTransformArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

@Observable public class DecomposeTransformArrayNode: StrategyNode
{
    public override class var name: String { "Transform Array Decompose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits an array of Transforms via one of several strategies: into per-element Translation/Rotation/Scale (TRS), or into four per-element column arrays." }

    public override class var strategies: [String] { ["TRS", "Columns"] }

    private static let allDynamicNames: Set<String> = [
        "inputTransforms",
        "outputTranslations", "outputScales", "outputRotations",
        "outputColumn0s", "outputColumn1s", "outputColumn2s", "outputColumn3s",
    ]

    public override func rebuildPorts(forStrategy strategy: String)
    {
        let wanted: [(name: String, port: Port)]
        switch strategy
        {
        case "TRS":
            wanted =
            [
                ("inputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Inlet, description: "Array of 4x4 transform matrices to decompose")),
                ("outputTranslations", NodePort<ContiguousArray<simd_float3>>(name: "Translations", kind: .Outlet, description: "Per-element translation as XYZ position")),
                ("outputScales", NodePort<ContiguousArray<simd_float3>>(name: "Scales", kind: .Outlet, description: "Per-element scale as XYZ scale factors")),
                ("outputRotations", NodePort<ContiguousArray<simd_float4>>(name: "Rotations", kind: .Outlet, description: "Per-element rotation as quaternion vector")),
            ]

        case "Columns":
            wanted =
            [
                ("inputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Inlet, description: "Array of 4x4 transform matrices to decompose")),
                ("outputColumn0s", NodePort<ContiguousArray<simd_float4>>(name: "Column 0s", kind: .Outlet, description: "Per-element first column of the matrix")),
                ("outputColumn1s", NodePort<ContiguousArray<simd_float4>>(name: "Column 1s", kind: .Outlet, description: "Per-element second column of the matrix")),
                ("outputColumn2s", NodePort<ContiguousArray<simd_float4>>(name: "Column 2s", kind: .Outlet, description: "Per-element third column of the matrix")),
                ("outputColumn3s", NodePort<ContiguousArray<simd_float4>>(name: "Column 3s", kind: .Outlet, description: "Per-element fourth column of the matrix (translation, when W=1)")),
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
        guard let inputTransforms: NodePort<ContiguousArray<simd_float4x4>> = findPort(named: "inputTransforms"),
              inputTransforms.valueDidChange
        else { return }

        let transforms = inputTransforms.value ?? ContiguousArray<simd_float4x4>()

        switch self.strategy
        {
        case "TRS":
            guard let outputTranslations: NodePort<ContiguousArray<simd_float3>> = findPort(named: "outputTranslations"),
                  let outputScales: NodePort<ContiguousArray<simd_float3>> = findPort(named: "outputScales"),
                  let outputRotations: NodePort<ContiguousArray<simd_float4>> = findPort(named: "outputRotations")
            else { return }

            var translations = ContiguousArray<simd_float3>(); translations.reserveCapacity(transforms.count)
            var scales = ContiguousArray<simd_float3>(); scales.reserveCapacity(transforms.count)
            var rotations = ContiguousArray<simd_float4>(); rotations.reserveCapacity(transforms.count)

            for transform in transforms {
                let translation = simd_make_float3(transform.columns.3)
                let sx = transform.columns.0
                let sy = transform.columns.1
                let sz = transform.columns.2

                let scale = simd_make_float3(simd_length(sx), simd_length(sy), simd_length(sz))
                let rx = simd_make_float3(sx) / scale.x
                let ry = simd_make_float3(sy) / scale.y
                let rz = simd_make_float3(sz) / scale.z

                let orientation = simd_quatf(simd_float3x3(rx, ry, rz)).normalized

                translations.append(translation)
                scales.append(scale)
                rotations.append(orientation.vector)
            }

            outputTranslations.send(translations)
            outputScales.send(scales)
            outputRotations.send(rotations)

        case "Columns":
            guard let outputColumn0s: NodePort<ContiguousArray<simd_float4>> = findPort(named: "outputColumn0s"),
                  let outputColumn1s: NodePort<ContiguousArray<simd_float4>> = findPort(named: "outputColumn1s"),
                  let outputColumn2s: NodePort<ContiguousArray<simd_float4>> = findPort(named: "outputColumn2s"),
                  let outputColumn3s: NodePort<ContiguousArray<simd_float4>> = findPort(named: "outputColumn3s")
            else { return }

            var c0s = ContiguousArray<simd_float4>(); c0s.reserveCapacity(transforms.count)
            var c1s = ContiguousArray<simd_float4>(); c1s.reserveCapacity(transforms.count)
            var c2s = ContiguousArray<simd_float4>(); c2s.reserveCapacity(transforms.count)
            var c3s = ContiguousArray<simd_float4>(); c3s.reserveCapacity(transforms.count)

            for transform in transforms {
                c0s.append(transform.columns.0)
                c1s.append(transform.columns.1)
                c2s.append(transform.columns.2)
                c3s.append(transform.columns.3)
            }

            outputColumn0s.send(c0s)
            outputColumn1s.send(c1s)
            outputColumn2s.send(c2s)
            outputColumn3s.send(c3s)

        default:
            break
        }
    }
}
