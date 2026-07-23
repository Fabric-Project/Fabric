//
//  DecomposeVectorArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class DecomposeVectorArrayNode: StrategyNode
{
    public override class var name: String { "Vector Array Decompose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits a vector array into per-element component arrays. Choose the vector type in Settings." }

    public override class var strategyOptions: [any NodeStrategyOption] { VectorType.allCases }

    private static let allDynamicNames: Set<String> = [
        "inputArray",
        "outputComponent0", "outputComponent1", "outputComponent2", "outputComponent3",
    ]

    public convenience init(context: Context, vectorType: VectorType)
    {
        self.init(context: context, strategy: vectorType)
    }

    override public var displayName: String? {
        guard let vt = VectorType.allCases.first(where: { $0.rawValue == strategy }) else { return nil }
        return "\(vt.portType.rawValue) Array Decompose"
    }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        guard let vt = VectorType.allCases.first(where: { $0.rawValue == strategy }) else { return }

        // Replace input port only when the vector type changes
        let arrayPortType = PortType.Array(portType: vt.portType)
        if let existing: Port = findPort(named: "inputArray"), existing.portType != arrayPortType {
            removePort(existing)
        }
        if findPort(named: "inputArray") == nil {
            let inputPort: Port
            switch vt {
            case .float2: inputPort = NodePort<ContiguousArray<simd_float2>>(name: "\(vt.portType.rawValue) Array", kind: .Inlet, description: "Array of \(vt.portType.rawValue) values to decompose")
            case .float3: inputPort = NodePort<ContiguousArray<simd_float3>>(name: "\(vt.portType.rawValue) Array", kind: .Inlet, description: "Array of \(vt.portType.rawValue) values to decompose")
            case .float4: inputPort = NodePort<ContiguousArray<simd_float4>>(name: "\(vt.portType.rawValue) Array", kind: .Inlet, description: "Array of \(vt.portType.rawValue) values to decompose")
            }
            addDynamicPort(inputPort, name: "inputArray")
        }

        // Remove component output ports beyond the needed count
        for i in vt.componentLabels.count..<4 {
            if let p: Port = findPort(named: "outputComponent\(i)") { removePort(p) }
        }
        // Add missing component output ports
        for (i, label) in vt.componentLabels.enumerated() {
            if findPort(named: "outputComponent\(i)") == nil {
                let p = NodePort<ContiguousArray<Float>>(name: label, kind: .Outlet, description: "\(label) component, one per element")
                addDynamicPort(p, name: "outputComponent\(i)")
            }
        }
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let vt = VectorType.allCases.first(where: { $0.rawValue == strategy }) else { return }

        func sendEmpty()
        {
            for i in 0..<vt.componentLabels.count {
                if let out: NodePort<ContiguousArray<Float>> = findPort(named: "outputComponent\(i)") {
                    out.send(ContiguousArray())
                }
            }
        }

        func sendComponentArrays(_ arrays: [ContiguousArray<Float>])
        {
            for (i, arr) in arrays.enumerated() {
                if let out: NodePort<ContiguousArray<Float>> = findPort(named: "outputComponent\(i)") {
                    out.send(arr)
                }
            }
        }

        switch vt {
        case .float2:
            guard let inp: NodePort<ContiguousArray<simd_float2>> = findPort(named: "inputArray"),
                  inp.valueDidChange else { return }
            guard let values = inp.value else { sendEmpty(); return }
            var xs = ContiguousArray<Float>(); xs.reserveCapacity(values.count)
            var ys = ContiguousArray<Float>(); ys.reserveCapacity(values.count)
            for v in values { xs.append(v.x); ys.append(v.y) }
            sendComponentArrays([xs, ys])

        case .float3:
            guard let inp: NodePort<ContiguousArray<simd_float3>> = findPort(named: "inputArray"),
                  inp.valueDidChange else { return }
            guard let values = inp.value else { sendEmpty(); return }
            var xs = ContiguousArray<Float>(); xs.reserveCapacity(values.count)
            var ys = ContiguousArray<Float>(); ys.reserveCapacity(values.count)
            var zs = ContiguousArray<Float>(); zs.reserveCapacity(values.count)
            for v in values { xs.append(v.x); ys.append(v.y); zs.append(v.z) }
            sendComponentArrays([xs, ys, zs])

        case .float4:
            guard let inp: NodePort<ContiguousArray<simd_float4>> = findPort(named: "inputArray"),
                  inp.valueDidChange else { return }
            guard let values = inp.value else { sendEmpty(); return }
            var xs = ContiguousArray<Float>(); xs.reserveCapacity(values.count)
            var ys = ContiguousArray<Float>(); ys.reserveCapacity(values.count)
            var zs = ContiguousArray<Float>(); zs.reserveCapacity(values.count)
            var ws = ContiguousArray<Float>(); ws.reserveCapacity(values.count)
            for v in values { xs.append(v.x); ys.append(v.y); zs.append(v.z); ws.append(v.w) }
            sendComponentArrays([xs, ys, zs, ws])
        }
    }
}
