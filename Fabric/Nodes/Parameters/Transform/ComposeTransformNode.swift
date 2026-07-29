//
//  ComposeTransformNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class ComposeTransformNode: StrategyNode
{
    public override class var name: String { "Transform Compose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Builds a Transform via one of several strategies: Position/Orientation/Scale (TRS), or directly from its four column vectors." }

    public override class var strategyOptions: [any NodeStrategyOption] { TransformCompositionMode.allCases }

    private static let allDynamicNames: Set<String> = [
        "inputPosition", "inputOrientation", "inputScale",
        "inputColumn0", "inputColumn1", "inputColumn2", "inputColumn3",
        "outputTransform",
    ]

    public override func rebuildPorts(forStrategy strategy: String)
    {
        let wanted: [(name: String, port: Port)]
        switch strategy
        {
        case "TRS":
            wanted =
            [
                ("inputPosition", ParameterPort(parameter: Float3Parameter("Position", simd_float3(0, 0, 0), .inputfield, "Position (XYZ)"))),
                ("inputOrientation", ParameterPort(parameter: Float4Parameter("Orientation", simd_float4(0, 0, 0, 1), .inputfield, "Quaternion orientation (X, Y, Z, W)"))),
                ("inputScale", ParameterPort(parameter: Float3Parameter("Scale", simd_float3(1, 1, 1), .inputfield, "Scale (XYZ)"))),
                ("outputTransform", NodePort<simd_float4x4>(name: "Transform", kind: .Outlet, description: "Model matrix (T*R*S)")),
            ]

        case "Columns":
            wanted =
            [
                ("inputColumn0", ParameterPort(parameter: Float4Parameter("Column 0", simd_float4(1, 0, 0, 0), .inputfield, "First column of the matrix"))),
                ("inputColumn1", ParameterPort(parameter: Float4Parameter("Column 1", simd_float4(0, 1, 0, 0), .inputfield, "Second column of the matrix"))),
                ("inputColumn2", ParameterPort(parameter: Float4Parameter("Column 2", simd_float4(0, 0, 1, 0), .inputfield, "Third column of the matrix"))),
                ("inputColumn3", ParameterPort(parameter: Float4Parameter("Column 3", simd_float4(0, 0, 0, 1), .inputfield, "Fourth column of the matrix (translation, when W=1)"))),
                ("outputTransform", NodePort<simd_float4x4>(name: "Transform", kind: .Outlet, description: "Matrix built from its four columns")),
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
    throws
    {
        guard let outputTransform: NodePort<simd_float4x4> = findPort(named: "outputTransform") else { return }

        switch self.strategy
        {
        case "TRS":
            guard let inputPosition: ParameterPort<simd_float3> = findPort(named: "inputPosition"),
                  let inputOrientation: ParameterPort<simd_float4> = findPort(named: "inputOrientation"),
                  let inputScale: ParameterPort<simd_float3> = findPort(named: "inputScale")
            else { return }
            guard inputPosition.valueDidChange || inputOrientation.valueDidChange || inputScale.valueDidChange else { return }

            let position = inputPosition.value ?? simd_float3(0, 0, 0)
            let orientation = simd_quatf(safeVector: inputOrientation.value ?? simd_float4(0, 0, 0, 1))
            let scale = inputScale.value ?? simd_float3(1, 1, 1)

            // T*R*S in closed form: scale the rotation's columns and drop the
            // position into the translation column (same derivation as
            // ComposeTransformArrayNode's TRS strategy).
            var m = matrix_float4x4(orientation)
            m.columns.0 *= scale.x
            m.columns.1 *= scale.y
            m.columns.2 *= scale.z
            m.columns.3 = simd_float4(position, 1)
            outputTransform.send(m)

        case "Columns":
            guard let inputColumn0: ParameterPort<simd_float4> = findPort(named: "inputColumn0"),
                  let inputColumn1: ParameterPort<simd_float4> = findPort(named: "inputColumn1"),
                  let inputColumn2: ParameterPort<simd_float4> = findPort(named: "inputColumn2"),
                  let inputColumn3: ParameterPort<simd_float4> = findPort(named: "inputColumn3")
            else { return }
            guard inputColumn0.valueDidChange || inputColumn1.valueDidChange
                || inputColumn2.valueDidChange || inputColumn3.valueDidChange
            else { return }

            let m = simd_float4x4(
                inputColumn0.value ?? simd_float4(1, 0, 0, 0),
                inputColumn1.value ?? simd_float4(0, 1, 0, 0),
                inputColumn2.value ?? simd_float4(0, 0, 1, 0),
                inputColumn3.value ?? simd_float4(0, 0, 0, 1)
            )
            outputTransform.send(m)

        default:
            break
        }
    }
}
