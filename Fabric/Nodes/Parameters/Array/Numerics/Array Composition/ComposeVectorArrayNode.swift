//
//  ComposeVectorArrayNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class ComposeVectorArrayNode: StrategyNode
{
    public override class var name: String { "Vector Array Compose" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Vector) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Zips component arrays into a vector array. Output length matches the longest input; shorter inputs pad with their last element. Choose the vector type in Settings." }

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
            + vt.componentLabels.enumerated().map { index, label in
                PortDeclaration(registryKey: "inputComponent\(index)",
                                port: NodePort<ContiguousArray<Float>>(name: label, kind: .Inlet, description: "\(label) component, one per element"))
            }
            + [PortDeclaration(registryKey: "outputArray", portType: .Array(portType: vt.portType), kind: .Outlet, name: "\(vt.portType.rawValue) Array", description: "Array of \(vt.portType.rawValue) values")]
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let vt: VectorType = strategyOption() else { return }

        let compCount = vt.componentLabels.count
        let anyChanged = (0..<compCount).contains { i in
            let p: NodePort<ContiguousArray<Float>>? = findPort(named: "inputComponent\(i)")
            return p?.valueDidChange == true
        }
        guard anyChanged else { return }

        func inPort(_ i: Int) -> ContiguousArray<Float>? {
            let p: NodePort<ContiguousArray<Float>>? = findPort(named: "inputComponent\(i)")
            return p?.value
        }

        let concurrentThreshold = 128

        switch vt {
        case .float2:
            guard let outPort: NodePort<ContiguousArray<simd_float2>> = findPort(named: "outputArray") else { return }
            let xs = inPort(0); let ys = inPort(1)
            let count = max(xs?.count ?? 0, ys?.count ?? 0)
            guard count > 0 else { outPort.send(ContiguousArray()); return }
            let xp = (xs ?? []).paddedToLast(count: count, fallback: 0)
            let yp = (ys ?? []).paddedToLast(count: count, fallback: 0)
            var out = ContiguousArray<simd_float2>(repeating: .zero, count: count)
            if count >= concurrentThreshold {
                out.withUnsafeMutableBufferPointer { buf in
                    DispatchQueue.concurrentPerform(iterations: count) { i in buf[i] = simd_float2(xp[i], yp[i]) }
                }
            } else {
                for i in 0..<count { out[i] = simd_float2(xp[i], yp[i]) }
            }
            outPort.send(out)

        case .float3:
            guard let outPort: NodePort<ContiguousArray<simd_float3>> = findPort(named: "outputArray") else { return }
            let xs = inPort(0); let ys = inPort(1); let zs = inPort(2)
            let count = max(xs?.count ?? 0, ys?.count ?? 0, zs?.count ?? 0)
            guard count > 0 else { outPort.send(ContiguousArray()); return }
            let xp = (xs ?? []).paddedToLast(count: count, fallback: 0)
            let yp = (ys ?? []).paddedToLast(count: count, fallback: 0)
            let zp = (zs ?? []).paddedToLast(count: count, fallback: 0)
            var out = ContiguousArray<simd_float3>(repeating: .zero, count: count)
            if count >= concurrentThreshold {
                out.withUnsafeMutableBufferPointer { buf in
                    DispatchQueue.concurrentPerform(iterations: count) { i in buf[i] = simd_float3(xp[i], yp[i], zp[i]) }
                }
            } else {
                for i in 0..<count { out[i] = simd_float3(xp[i], yp[i], zp[i]) }
            }
            outPort.send(out)

        case .float4:
            guard let outPort: NodePort<ContiguousArray<simd_float4>> = findPort(named: "outputArray") else { return }
            let xs = inPort(0); let ys = inPort(1); let zs = inPort(2); let ws = inPort(3)
            let count = max(xs?.count ?? 0, ys?.count ?? 0, zs?.count ?? 0, ws?.count ?? 0)
            guard count > 0 else { outPort.send(ContiguousArray()); return }
            let xp = (xs ?? []).paddedToLast(count: count, fallback: 0)
            let yp = (ys ?? []).paddedToLast(count: count, fallback: 0)
            let zp = (zs ?? []).paddedToLast(count: count, fallback: 0)
            let wp = (ws ?? []).paddedToLast(count: count, fallback: 0)
            var out = ContiguousArray<simd_float4>(repeating: .zero, count: count)
            if count >= concurrentThreshold {
                out.withUnsafeMutableBufferPointer { buf in
                    DispatchQueue.concurrentPerform(iterations: count) { i in buf[i] = simd_float4(xp[i], yp[i], zp[i], wp[i]) }
                }
            } else {
                for i in 0..<count { out[i] = simd_float4(xp[i], yp[i], zp[i], wp[i]) }
            }
            outPort.send(out)
        }
    }
}
