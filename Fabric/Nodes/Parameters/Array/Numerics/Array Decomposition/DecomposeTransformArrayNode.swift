//
//  DecomposeTransformArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class DecomposeTransformArrayNode: StrategyNode
{
    public override class var name: String { "Transform Array Decompose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits an array of Transforms via one of several strategies: into per-element Translation/Rotation/Scale (TRS), or into four per-element column arrays." }

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
                ("inputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Inlet, description: "Array of 4x4 transform matrices to decompose")),
                ("outputTranslations", NodePort<ContiguousArray<simd_float3>>(name: "Translations", kind: .Outlet, description: "Per-element translation as XYZ position")),
                ("outputScales", NodePort<ContiguousArray<simd_float3>>(name: "Scales", kind: .Outlet, description: "Per-element scale as XYZ scale factors")),
                ("outputRotations", NodePort<ContiguousArray<simd_float4>>(name: "Rotations", kind: .Outlet, description: "Per-element rotation as quaternion vector")),
            ]

        case .columns:
            wanted =
            [
                ("inputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Inlet, description: "Array of 4x4 transform matrices to decompose")),
                ("outputColumn0s", NodePort<ContiguousArray<simd_float4>>(name: "Column 0s", kind: .Outlet, description: "Per-element first column of the matrix")),
                ("outputColumn1s", NodePort<ContiguousArray<simd_float4>>(name: "Column 1s", kind: .Outlet, description: "Per-element second column of the matrix")),
                ("outputColumn2s", NodePort<ContiguousArray<simd_float4>>(name: "Column 2s", kind: .Outlet, description: "Per-element third column of the matrix")),
                ("outputColumn3s", NodePort<ContiguousArray<simd_float4>>(name: "Column 3s", kind: .Outlet, description: "Per-element fourth column of the matrix (translation, when W=1)")),
            ]

        case nil:
            wanted = []
        }

        return super.declaredPorts() + wanted.map { PortDeclaration(key: $0.name, port: $0.port) }
    }

    private var boundInputTransforms: NodePort<ContiguousArray<simd_float4x4>>?
    private var boundOutputTranslations: NodePort<ContiguousArray<simd_float3>>?
    private var boundOutputScales: NodePort<ContiguousArray<simd_float3>>?
    private var boundOutputRotations: NodePort<ContiguousArray<simd_float4>>?
    private var boundOutputColumn0s: NodePort<ContiguousArray<simd_float4>>?
    private var boundOutputColumn1s: NodePort<ContiguousArray<simd_float4>>?
    private var boundOutputColumn2s: NodePort<ContiguousArray<simd_float4>>?
    private var boundOutputColumn3s: NodePort<ContiguousArray<simd_float4>>?

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputTransforms = findPort(named: "inputTransforms")
        self.boundOutputTranslations = findPort(named: "outputTranslations")
        self.boundOutputScales = findPort(named: "outputScales")
        self.boundOutputRotations = findPort(named: "outputRotations")
        self.boundOutputColumn0s = findPort(named: "outputColumn0s")
        self.boundOutputColumn1s = findPort(named: "outputColumn1s")
        self.boundOutputColumn2s = findPort(named: "outputColumn2s")
        self.boundOutputColumn3s = findPort(named: "outputColumn3s")
    }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputTransforms: NodePort<ContiguousArray<simd_float4x4>> = self.boundInputTransforms,
              inputTransforms.valueDidChange
        else { return }

        let transforms = inputTransforms.value ?? ContiguousArray<simd_float4x4>()

        switch typedStrategy
        {
        case .trs:
            guard let outputTranslations: NodePort<ContiguousArray<simd_float3>> = self.boundOutputTranslations,
                  let outputScales: NodePort<ContiguousArray<simd_float3>> = self.boundOutputScales,
                  let outputRotations: NodePort<ContiguousArray<simd_float4>> = self.boundOutputRotations
            else { return }

            var translations = ContiguousArray<simd_float3>(); translations.reserveCapacity(transforms.count)
            var scales = ContiguousArray<simd_float3>(); scales.reserveCapacity(transforms.count)
            var rotations = ContiguousArray<simd_float4>(); rotations.reserveCapacity(transforms.count)

            for transform in transforms {
                let (translation, orientation, scale) = transform.decomposed

                translations.append(translation)
                scales.append(scale)
                rotations.append(orientation.vector)
            }

            outputTranslations.send(translations)
            outputScales.send(scales)
            outputRotations.send(rotations)

        case .columns:
            guard let outputColumn0s: NodePort<ContiguousArray<simd_float4>> = self.boundOutputColumn0s,
                  let outputColumn1s: NodePort<ContiguousArray<simd_float4>> = self.boundOutputColumn1s,
                  let outputColumn2s: NodePort<ContiguousArray<simd_float4>> = self.boundOutputColumn2s,
                  let outputColumn3s: NodePort<ContiguousArray<simd_float4>> = self.boundOutputColumn3s
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

        case nil:
            break
        }
    }
}
