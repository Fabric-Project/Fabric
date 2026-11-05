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

    /// `strategy`, typed before each reconcile, so execute switches on it without a cast.
    private var typedStrategy: TransformCompositionMode?

    override public func prepareDeclarations()
    {
        super.prepareDeclarations()
        typedStrategy = strategyOption(as: TransformCompositionMode.self)
    }

    override public func declaredPorts() -> [PortDeclaration]
    {
        let wanted: [(name: String, port: Port)]
        switch typedStrategy
        {
        case .trs:
            wanted =
            [
                ("inputPosition", ParameterPort(parameter: Float3Parameter("Position", simd_float3(0, 0, 0), .inputfield, "Position (XYZ)"))),
                ("inputOrientation", ParameterPort(parameter: Float4Parameter("Orientation", simd_float4(0, 0, 0, 1), .inputfield, "Quaternion orientation (X, Y, Z, W)"))),
                ("inputScale", ParameterPort(parameter: Float3Parameter("Scale", simd_float3(1, 1, 1), .inputfield, "Scale (XYZ)"))),
                ("outputTransform", NodePort<simd_float4x4>(name: "Transform", kind: .Outlet, description: "Model matrix (T*R*S)")),
            ]

        case .columns:
            wanted =
            [
                ("inputColumn0", ParameterPort(parameter: Float4Parameter("Column 0", simd_float4(1, 0, 0, 0), .inputfield, "First column of the matrix"))),
                ("inputColumn1", ParameterPort(parameter: Float4Parameter("Column 1", simd_float4(0, 1, 0, 0), .inputfield, "Second column of the matrix"))),
                ("inputColumn2", ParameterPort(parameter: Float4Parameter("Column 2", simd_float4(0, 0, 1, 0), .inputfield, "Third column of the matrix"))),
                ("inputColumn3", ParameterPort(parameter: Float4Parameter("Column 3", simd_float4(0, 0, 0, 1), .inputfield, "Fourth column of the matrix (translation, when W=1)"))),
                ("outputTransform", NodePort<simd_float4x4>(name: "Transform", kind: .Outlet, description: "Matrix built from its four columns")),
            ]

        case nil:
            wanted = []
        }

        return super.declaredPorts() + wanted.map { PortDeclaration(key: $0.name, port: $0.port) }
    }

    private var boundOutputTransform: NodePort<simd_float4x4>?
    private var boundInputPosition: ParameterPort<simd_float3>?
    private var boundInputOrientation: ParameterPort<simd_float4>?
    private var boundInputScale: ParameterPort<simd_float3>?
    private var boundInputColumn0: ParameterPort<simd_float4>?
    private var boundInputColumn1: ParameterPort<simd_float4>?
    private var boundInputColumn2: ParameterPort<simd_float4>?
    private var boundInputColumn3: ParameterPort<simd_float4>?

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundOutputTransform = findPort(named: "outputTransform")
        self.boundInputPosition = findPort(named: "inputPosition")
        self.boundInputOrientation = findPort(named: "inputOrientation")
        self.boundInputScale = findPort(named: "inputScale")
        self.boundInputColumn0 = findPort(named: "inputColumn0")
        self.boundInputColumn1 = findPort(named: "inputColumn1")
        self.boundInputColumn2 = findPort(named: "inputColumn2")
        self.boundInputColumn3 = findPort(named: "inputColumn3")
    }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let outputTransform: NodePort<simd_float4x4> = self.boundOutputTransform else { return }

        switch typedStrategy
        {
        case .trs:
            guard let inputPosition: ParameterPort<simd_float3> = self.boundInputPosition,
                  let inputOrientation: ParameterPort<simd_float4> = self.boundInputOrientation,
                  let inputScale: ParameterPort<simd_float3> = self.boundInputScale
            else { return }
            guard inputPosition.valueDidChange || inputOrientation.valueDidChange || inputScale.valueDidChange else { return }

            let position = inputPosition.value ?? simd_float3(0, 0, 0)
            let orientation = simd_quatf(safeVector: inputOrientation.value ?? simd_float4(0, 0, 0, 1))
            let scale = inputScale.value ?? simd_float3(1, 1, 1)

            outputTransform.send(simd_float4x4(translation: position, rotation: orientation, scale: scale))

        case .columns:
            guard let inputColumn0: ParameterPort<simd_float4> = self.boundInputColumn0,
                  let inputColumn1: ParameterPort<simd_float4> = self.boundInputColumn1,
                  let inputColumn2: ParameterPort<simd_float4> = self.boundInputColumn2,
                  let inputColumn3: ParameterPort<simd_float4> = self.boundInputColumn3
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

        case nil:
            break
        }
    }
}
