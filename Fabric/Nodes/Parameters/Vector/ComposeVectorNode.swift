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

    private static let allDynamicNames: Set<String> = [
        "inputComponent0", "inputComponent1", "inputComponent2", "inputComponent3",
        "outputVector",
    ]

    public convenience init(context: Context, vectorType: VectorType)
    {
        self.init(context: context, strategy: vectorType)
    }

    override public var displayName: String? {
        guard let vt = VectorType.allCases.first(where: { $0.rawValue == strategy }) else { return nil }
        return "\(vt.portType.rawValue) Compose"
    }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        guard let vt = VectorType.allCases.first(where: { $0.rawValue == strategy }) else { return }

        // Remove component ports beyond the needed count
        for i in vt.componentLabels.count..<4 {
            if let p: Port = findPort(named: "inputComponent\(i)") { removePort(p) }
        }
        // Add missing component ports
        for (i, label) in vt.componentLabels.enumerated() {
            if findPort(named: "inputComponent\(i)") == nil {
                let p = ParameterPort(parameter: FloatParameter(label, 0.0, .inputfield, "\(label) component"))
                addDynamicPort(p, name: "inputComponent\(i)")
            }
        }

        // Replace output port only when the vector type changes
        if let existing: Port = findPort(named: "outputVector"), existing.portType != vt.portType {
            removePort(existing)
        }
        if findPort(named: "outputVector") == nil {
            let outputPort: Port
            switch vt {
            case .float2: outputPort = NodePort<simd_float2>(name: vt.portType.rawValue, kind: .Outlet, description: "Combined \(vt.portType.rawValue)")
            case .float3: outputPort = NodePort<simd_float3>(name: vt.portType.rawValue, kind: .Outlet, description: "Combined \(vt.portType.rawValue)")
            case .float4: outputPort = NodePort<simd_float4>(name: vt.portType.rawValue, kind: .Outlet, description: "Combined \(vt.portType.rawValue)")
            }
            addDynamicPort(outputPort, name: "outputVector")
        }
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let vt = VectorType.allCases.first(where: { $0.rawValue == strategy }) else { return }

        let compCount = vt.componentLabels.count
        let anyChanged = (0..<compCount).contains { i in
            let p: ParameterPort<Float>? = findPort(named: "inputComponent\(i)")
            return p?.valueDidChange == true
        }
        guard anyChanged else { return }

        func comp(_ i: Int) -> Float {
            let p: ParameterPort<Float>? = findPort(named: "inputComponent\(i)")
            return p?.value ?? 0
        }

        switch vt {
        case .float2:
            if let out: NodePort<simd_float2> = findPort(named: "outputVector") {
                out.send(simd_float2(comp(0), comp(1)))
            }
        case .float3:
            if let out: NodePort<simd_float3> = findPort(named: "outputVector") {
                out.send(simd_float3(comp(0), comp(1), comp(2)))
            }
        case .float4:
            if let out: NodePort<simd_float4> = findPort(named: "outputVector") {
                out.send(simd_float4(comp(0), comp(1), comp(2), comp(3)))
            }
        }
    }
}
