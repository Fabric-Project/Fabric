//
//  DecomposeVectorNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class DecomposeVectorNode: StrategyNode
{
    public override class var name: String { "Vector Decompose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits a vector into its X/Y/Z/W components. Choose the vector type in Settings." }

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
        guard let vt: VectorType = Self.strategyOption(matching: strategy) else { return super.declaredPorts() }

        return super.declaredPorts()
            + [PortDeclaration(registryKey: "inputVector", portType: vt.portType, kind: .Inlet, name: vt.portType.rawValue, description: "Vector to decompose")]
            + vt.componentLabels.enumerated().map { index, label in
                PortDeclaration(registryKey: "outputComponent\(index)",
                                port: NodePort<Float>(name: label, kind: .Outlet, description: "\(label) component"))
            }
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let vt: VectorType = strategyOption() else { return }

        func sendComponents(_ values: [Float])
        {
            for (i, value) in values.enumerated() {
                if let out: NodePort<Float> = findPort(named: "outputComponent\(i)") {
                    out.send(value)
                }
            }
        }

        switch vt {
        case .float2:
            guard let inp: ParameterPort<simd_float2> = findPort(named: "inputVector"),
                  inp.valueDidChange, let v = inp.value else { return }
            sendComponents([v.x, v.y])
        case .float3:
            guard let inp: ParameterPort<simd_float3> = findPort(named: "inputVector"),
                  inp.valueDidChange, let v = inp.value else { return }
            sendComponents([v.x, v.y, v.z])
        case .float4:
            guard let inp: ParameterPort<simd_float4> = findPort(named: "inputVector"),
                  inp.valueDidChange, let v = inp.value else { return }
            sendComponents([v.x, v.y, v.z, v.w])
        }
    }
}
