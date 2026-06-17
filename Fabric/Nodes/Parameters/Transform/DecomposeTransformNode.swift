//
//  DecomposeTransformNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

@Observable public class DecomposeTransformNode: StrategyNode
{
    override public class var name: String { "Transform Decompose" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits a Transform via one of several strategies: into its Translation/Rotation/Scale (TRS), or into its four column vectors." }

    public override class var strategies: [String] { ["TRS", "Columns"] }

    private static let allDynamicNames: Set<String> = [
        "inputTransform",
        "outputTranslation", "outputScale", "outputRotation",
        "outputColumn0", "outputColumn1", "outputColumn2", "outputColumn3",
    ]

    public override func rebuildPorts(forStrategy strategy: String)
    {
        let wanted: [(name: String, port: Port)]
        switch strategy
        {
        case "TRS":
            wanted =
            [
                ("inputTransform", NodePort<simd_float4x4>(name: "Transform", kind: .Inlet, description: "4x4 transform matrix to decompose")),
                ("outputTranslation", NodePort<simd_float3>(name: "Translation", kind: .Outlet, description: "Translation component as XYZ position")),
                ("outputScale", NodePort<simd_float3>(name: "Scale", kind: .Outlet, description: "Scale component as XYZ scale factors")),
                ("outputRotation", NodePort<simd_float4>(name: "Rotation", kind: .Outlet, description: "Rotation component as quaternion vector")),
            ]

        case "Columns":
            wanted =
            [
                ("inputTransform", NodePort<simd_float4x4>(name: "Transform", kind: .Inlet, description: "4x4 transform matrix to decompose")),
                ("outputColumn0", NodePort<simd_float4>(name: "Column 0", kind: .Outlet, description: "First column of the matrix")),
                ("outputColumn1", NodePort<simd_float4>(name: "Column 1", kind: .Outlet, description: "Second column of the matrix")),
                ("outputColumn2", NodePort<simd_float4>(name: "Column 2", kind: .Outlet, description: "Third column of the matrix")),
                ("outputColumn3", NodePort<simd_float4>(name: "Column 3", kind: .Outlet, description: "Fourth column of the matrix (translation, when W=1)")),
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

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let inputTransform: NodePort<simd_float4x4> = findPort(named: "inputTransform"),
              inputTransform.valueDidChange,
              let transform = inputTransform.value
        else { return }

        switch self.strategy
        {
        case "TRS":
            guard let outputTranslation: NodePort<simd_float3> = findPort(named: "outputTranslation"),
                  let outputScale: NodePort<simd_float3> = findPort(named: "outputScale"),
                  let outputRotation: NodePort<simd_float4> = findPort(named: "outputRotation")
            else { return }

            let translation = simd_make_float3(transform.columns.3)
            let sx = transform.columns.0
            let sy = transform.columns.1
            let sz = transform.columns.2

            let scale = simd_make_float3(simd_length(sx), simd_length(sy), simd_length(sz))
            let rx = simd_make_float3(sx) / scale.x
            let ry = simd_make_float3(sy) / scale.y
            let rz = simd_make_float3(sz) / scale.z

            let orientation = simd_quatf(simd_float3x3(rx, ry, rz)).normalized

            outputTranslation.send(translation)
            outputScale.send(scale)
            outputRotation.send(orientation.vector)

        case "Columns":
            guard let outputColumn0: NodePort<simd_float4> = findPort(named: "outputColumn0"),
                  let outputColumn1: NodePort<simd_float4> = findPort(named: "outputColumn1"),
                  let outputColumn2: NodePort<simd_float4> = findPort(named: "outputColumn2"),
                  let outputColumn3: NodePort<simd_float4> = findPort(named: "outputColumn3")
            else { return }

            outputColumn0.send(transform.columns.0)
            outputColumn1.send(transform.columns.1)
            outputColumn2.send(transform.columns.2)
            outputColumn3.send(transform.columns.3)

        default:
            break
        }
    }
}
