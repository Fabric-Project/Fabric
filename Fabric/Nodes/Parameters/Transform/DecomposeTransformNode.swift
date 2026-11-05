//
//  DecomposeTransformNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class DecomposeTransformNode: StrategyNode
{
    override public class var name: String { "Transform Decompose" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits a Transform via one of several strategies: into its Translation/Rotation/Scale (TRS), or into its four column vectors." }

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
                ("inputTransform", PortType.Transform.makeFreshPort(name: "Transform", kind: .Inlet, description: "4x4 transform matrix to decompose")),
                ("outputTranslation", NodePort<simd_float3>(name: "Translation", kind: .Outlet, description: "Translation component as XYZ position")),
                ("outputScale", NodePort<simd_float3>(name: "Scale", kind: .Outlet, description: "Scale component as XYZ scale factors")),
                ("outputRotation", NodePort<simd_float4>(name: "Rotation", kind: .Outlet, description: "Rotation component as quaternion vector")),
            ]

        case .columns:
            wanted =
            [
                ("inputTransform", PortType.Transform.makeFreshPort(name: "Transform", kind: .Inlet, description: "4x4 transform matrix to decompose")),
                ("outputColumn0", NodePort<simd_float4>(name: "Column 0", kind: .Outlet, description: "First column of the matrix")),
                ("outputColumn1", NodePort<simd_float4>(name: "Column 1", kind: .Outlet, description: "Second column of the matrix")),
                ("outputColumn2", NodePort<simd_float4>(name: "Column 2", kind: .Outlet, description: "Third column of the matrix")),
                ("outputColumn3", NodePort<simd_float4>(name: "Column 3", kind: .Outlet, description: "Fourth column of the matrix (translation, when W=1)")),
            ]

        case nil:
            wanted = []
        }

        return super.declaredPorts() + wanted.map { PortDeclaration(key: $0.name, port: $0.port) }
    }

    private var boundInputTransform: NodePort<simd_float4x4>?
    private var boundOutputTranslation: NodePort<simd_float3>?
    private var boundOutputScale: NodePort<simd_float3>?
    private var boundOutputRotation: NodePort<simd_float4>?
    private var boundOutputColumn0: NodePort<simd_float4>?
    private var boundOutputColumn1: NodePort<simd_float4>?
    private var boundOutputColumn2: NodePort<simd_float4>?
    private var boundOutputColumn3: NodePort<simd_float4>?

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputTransform = findPort(named: "inputTransform")
        self.boundOutputTranslation = findPort(named: "outputTranslation")
        self.boundOutputScale = findPort(named: "outputScale")
        self.boundOutputRotation = findPort(named: "outputRotation")
        self.boundOutputColumn0 = findPort(named: "outputColumn0")
        self.boundOutputColumn1 = findPort(named: "outputColumn1")
        self.boundOutputColumn2 = findPort(named: "outputColumn2")
        self.boundOutputColumn3 = findPort(named: "outputColumn3")
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputTransform: NodePort<simd_float4x4> = self.boundInputTransform,
              inputTransform.valueDidChange,
              let transform = inputTransform.value
        else { return }

        switch typedStrategy
        {
        case .trs:
            guard let outputTranslation: NodePort<simd_float3> = self.boundOutputTranslation,
                  let outputScale: NodePort<simd_float3> = self.boundOutputScale,
                  let outputRotation: NodePort<simd_float4> = self.boundOutputRotation
            else { return }

            let (translation, orientation, scale) = transform.decomposed

            outputTranslation.send(translation)
            outputScale.send(scale)
            outputRotation.send(orientation.vector)

        case .columns:
            guard let outputColumn0: NodePort<simd_float4> = self.boundOutputColumn0,
                  let outputColumn1: NodePort<simd_float4> = self.boundOutputColumn1,
                  let outputColumn2: NodePort<simd_float4> = self.boundOutputColumn2,
                  let outputColumn3: NodePort<simd_float4> = self.boundOutputColumn3
            else { return }

            outputColumn0.send(transform.columns.0)
            outputColumn1.send(transform.columns.1)
            outputColumn2.send(transform.columns.2)
            outputColumn3.send(transform.columns.3)

        case nil:
            break
        }
    }
}
