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
        guard let vt = strategy as? VectorType else { return super.declaredPorts() }

        return super.declaredPorts()
            + [PortDeclaration(key: "inputArray", portType: .Array(portType: vt.portType), kind: .Inlet, name: "\(vt.portType.rawValue) Array", description: "Array of \(vt.portType.rawValue) values to decompose")]
            + vt.componentLabels.enumerated().map { index, label in
                PortDeclaration(key: "outputComponent\(index)",
                                port: NodePort<ContiguousArray<Float>>(name: label, kind: .Outlet, description: "\(label) component, one per element"))
            }
    }

    private var vectorType: VectorType?
    private var outputs: [NodePort<ContiguousArray<Float>>] = []
    private var input2: NodePort<ContiguousArray<simd_float2>>?
    private var input3: NodePort<ContiguousArray<simd_float3>>?
    private var input4: NodePort<ContiguousArray<simd_float4>>?

    override public func prepareDeclarations()
    {
        super.prepareDeclarations()
        self.vectorType = self.strategyOption()
    }

    override public func bindPorts()
    {
        super.bindPorts()
        self.outputs = (0..<4).compactMap { findPort(named: "outputComponent\($0)") }
        self.input2 = findPort(named: "inputArray")
        self.input3 = findPort(named: "inputArray")
        self.input4 = findPort(named: "inputArray")
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let vt = vectorType else { return }

        func sendEmpty()
        {
            for output in outputs { output.send(ContiguousArray()) }
        }

        func sendComponentArrays(_ arrays: [ContiguousArray<Float>])
        {
            for (output, array) in zip(outputs, arrays) { output.send(array) }
        }

        switch vt {
        case .float2:
            guard let inp = input2,
                  inp.valueDidChange else { return }
            guard let values = inp.value else { sendEmpty(); return }
            var xs = ContiguousArray<Float>(); xs.reserveCapacity(values.count)
            var ys = ContiguousArray<Float>(); ys.reserveCapacity(values.count)
            for v in values { xs.append(v.x); ys.append(v.y) }
            sendComponentArrays([xs, ys])

        case .float3:
            guard let inp = input3,
                  inp.valueDidChange else { return }
            guard let values = inp.value else { sendEmpty(); return }
            var xs = ContiguousArray<Float>(); xs.reserveCapacity(values.count)
            var ys = ContiguousArray<Float>(); ys.reserveCapacity(values.count)
            var zs = ContiguousArray<Float>(); zs.reserveCapacity(values.count)
            for v in values { xs.append(v.x); ys.append(v.y); zs.append(v.z) }
            sendComponentArrays([xs, ys, zs])

        case .float4:
            guard let inp = input4,
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
