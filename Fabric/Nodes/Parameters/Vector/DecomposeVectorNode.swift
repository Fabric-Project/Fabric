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
    override public var displayName: String? { nil }

    private static let allDynamicNames: Set<String> = [
        "inputVector",
        "outputComponent0", "outputComponent1", "outputComponent2", "outputComponent3",
    ]

    public convenience init(context: Context, vectorType: VectorType)
    {
        self.init(context: context, strategy: vectorType)
    }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        guard let vt: VectorType = Self.strategyOption(matching: strategy) else { return }

        // Replace input port only when the vector type changes
        if let existing: Port = findPort(named: "inputVector"), existing.portType != vt.portType {
            removePort(existing)
        }
        if findPort(named: "inputVector") == nil {
            let inputPort: Port
            switch vt {
            case .float2: inputPort = NodePort<simd_float2>(name: vt.portType.rawValue, kind: .Inlet, description: "Vector to decompose")
            case .float3: inputPort = NodePort<simd_float3>(name: vt.portType.rawValue, kind: .Inlet, description: "Vector to decompose")
            case .float4: inputPort = NodePort<simd_float4>(name: vt.portType.rawValue, kind: .Inlet, description: "Vector to decompose")
            }
            addDynamicPort(inputPort, name: "inputVector")
        }

        // Remove component output ports beyond the needed count
        for i in vt.componentLabels.count..<4 {
            if let p: Port = findPort(named: "outputComponent\(i)") { removePort(p) }
        }
        // Add missing component output ports
        for (i, label) in vt.componentLabels.enumerated() {
            if findPort(named: "outputComponent\(i)") == nil {
                let p = NodePort<Float>(name: label, kind: .Outlet, description: "\(label) component")
                addDynamicPort(p, name: "outputComponent\(i)")
            }
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
            guard let inp: NodePort<simd_float2> = findPort(named: "inputVector"),
                  inp.valueDidChange, let v = inp.value else { return }
            sendComponents([v.x, v.y])
        case .float3:
            guard let inp: NodePort<simd_float3> = findPort(named: "inputVector"),
                  inp.valueDidChange, let v = inp.value else { return }
            sendComponents([v.x, v.y, v.z])
        case .float4:
            guard let inp: NodePort<simd_float4> = findPort(named: "inputVector"),
                  inp.valueDidChange, let v = inp.value else { return }
            sendComponents([v.x, v.y, v.z, v.w])
        }
    }
}
