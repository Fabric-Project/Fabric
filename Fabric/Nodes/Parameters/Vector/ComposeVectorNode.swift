//
//  ComposeVectorNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class ComposeVectorNode: StrategyNode
{
    public override class var name: String { "Vector Compose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Combines X/Y/Z/W components into a vector. Choose the vector type in Settings." }

    public override class var strategyOptions: [any NodeStrategyOption] { VectorType.allCases }

    // The vector type is already evident from the component ports, so keep the
    // plain type-name title rather than leading it with the strategy.
    override public func deriveSubtitle() -> String? { nil }

    public convenience init(context: Context, vectorType: VectorType)
    {
        self.init(context: context, strategy: vectorType)
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        guard let vt = strategy as? VectorType else { return super.declaredPorts() }

        return super.declaredPorts()
            + vt.componentLabels.enumerated().map { index, label in
                PortDeclaration(key: "inputComponent\(index)",
                                port: ParameterPort(parameter: FloatParameter(label, 0.0, .inputfield, "\(label) component")))
            }
            + [PortDeclaration(key: "outputVector", portType: vt.portType, kind: .Outlet, name: vt.portType.rawValue, description: "Combined \(vt.portType.rawValue)")]
    }

    private var vectorType: VectorType?
    private var components: [ParameterPort<Float>] = []
    private var output2: NodePort<simd_float2>?
    private var output3: NodePort<simd_float3>?
    private var output4: NodePort<simd_float4>?

    override public func prepareDeclarations()
    {
        super.prepareDeclarations()
        self.vectorType = self.strategyOption()
    }

    override public func bindPorts()
    {
        super.bindPorts()
        self.components = (0..<4).compactMap { findPort(named: "inputComponent\($0)") }
        self.output2 = findPort(named: "outputVector")
        self.output3 = findPort(named: "outputVector")
        self.output4 = findPort(named: "outputVector")
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let vectorType, components.contains(where: \.valueDidChange) else { return }

        func comp(_ i: Int) -> Float { i < components.count ? components[i].value ?? 0 : 0 }

        switch vectorType {
        case .float2: output2?.send(simd_float2(comp(0), comp(1)))
        case .float3: output3?.send(simd_float3(comp(0), comp(1), comp(2)))
        case .float4: output4?.send(simd_float4(comp(0), comp(1), comp(2), comp(3)))
        }
    }
}
