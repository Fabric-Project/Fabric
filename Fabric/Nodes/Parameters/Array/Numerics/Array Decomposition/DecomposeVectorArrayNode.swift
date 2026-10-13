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
            + [PortDeclaration(registryKey: "inputArray", portType: .Array(portType: vt.portType), kind: .Inlet, name: "\(vt.portType.rawValue) Array", description: "Array of \(vt.portType.rawValue) values to decompose")]
            + vt.componentLabels.enumerated().map { index, label in
                PortDeclaration(registryKey: "outputComponent\(index)",
                                port: NodePort<ContiguousArray<Float>>(name: label, kind: .Outlet, description: "\(label) component, one per element"))
            }
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let vt: VectorType = strategyOption() else { return }

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
