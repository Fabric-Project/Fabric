//
//  TransformArrayBlendNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// Whether an array operation takes one factor for every element or one per element.
public enum ArrayFactorMode: String, NodeStrategyOption, CaseIterable
{
    case single = "Single"
    case perElement = "Per Element"
}

public class TransformArrayBlendNode: StrategyNode
{
    public override class var name: String { "Transform Array Blend" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Blends two arrays of Transforms per element without skewing: translation and scale mix linearly, rotation slerps. Factor 0 is A, 1 is B. Settings: one Factor for every element, or a Factors array with one per element (resampled when its length differs). Output length matches the longer input; the shorter input pads with identity." }

    public override class var strategyOptions: [any NodeStrategyOption] { ArrayFactorMode.allCases }

    /// The title reads "Transform Array Blend" for one factor, and names the array otherwise.
    override public func deriveSubtitle() -> String?
    {
        strategyOption(as: ArrayFactorMode.self) == .perElement ? ArrayFactorMode.perElement.rawValue : nil
    }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        super.registerPorts(context: context) +
        [
            ("inputA", NodePort<ContiguousArray<simd_float4x4>>(name: "A", kind: .Inlet, description: "The Transforms at factor 0")),
            ("inputB", NodePort<ContiguousArray<simd_float4x4>>(name: "B", kind: .Inlet, description: "The Transforms at factor 1")),
            ("outputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Outlet, description: "The blended Transforms")),
        ]
    }

    public var inputA: NodePort<ContiguousArray<simd_float4x4>> { port(named: "inputA") }
    public var inputB: NodePort<ContiguousArray<simd_float4x4>> { port(named: "inputB") }
    public var outputTransforms: NodePort<ContiguousArray<simd_float4x4>> { port(named: "outputTransforms") }

    private static let allDynamicNames: Set<String> = ["inputFactor", "inputFactors"]

    public override func rebuildPorts(forStrategy strategy: String)
    {
        let wanted: (name: String, port: Port)
        switch ArrayFactorMode(rawValue: strategy) ?? .single
        {
        case .single:
            wanted = ("inputFactor", ParameterPort(parameter: FloatParameter("Factor", 0.5, .inputfield, "0 is A, 1 is B; not clamped")))
        case .perElement:
            wanted = ("inputFactors", NodePort<ContiguousArray<Float>>(name: "Factors", kind: .Inlet, description: "One factor per element; 0 is A, 1 is B. Resampled when its length differs from the Transforms"))
        }
        for name in Self.allDynamicNames where name != wanted.name
        {
            if let p = findPort(named: name) { removePort(p) }
        }
        if findPort(named: wanted.name) == nil
        {
            addDynamicPort(wanted.port, name: wanted.name)
        }
        markDirty()
    }

    /// `a` and `b` blended per element by `factors[i]`, as long as the longer array; a
    /// missing transform is identity and a missing factor is the last one given. Each pair
    /// blends with `simd_float4x4.lerp`, so the results stay rigid at any factor.
    public static func blended(_ a: ContiguousArray<simd_float4x4>, _ b: ContiguousArray<simd_float4x4>, factors: ContiguousArray<Float>) -> ContiguousArray<simd_float4x4>
    {
        let count = max(a.count, b.count)
        var output = ContiguousArray<simd_float4x4>()
        output.reserveCapacity(count)
        for index in 0..<count
        {
            let first = index < a.count ? a[index] : matrix_identity_float4x4
            let second = index < b.count ? b[index] : matrix_identity_float4x4
            let factor = index < factors.count ? factors[index] : (factors.last ?? 0)
            output.append(.lerp(first, second, factor.isFinite ? factor : 0))
        }
        return output
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let factorChanged = Self.allDynamicNames.contains { name in (findPort(named: name) as Port?)?.valueDidChange ?? false }
        guard self.inputA.valueDidChange || self.inputB.valueDidChange || factorChanged else { return }

        let a = self.inputA.value ?? []
        let b = self.inputB.value ?? []
        let count = max(a.count, b.count)
        let factors: ContiguousArray<Float>
        switch strategyOption(as: ArrayFactorMode.self) ?? .single
        {
        case .single:
            let factor: ParameterPort<Float>? = findPort(named: "inputFactor")
            factors = [factor?.value ?? 0.5]
        case .perElement:
            let factorArray: NodePort<ContiguousArray<Float>>? = findPort(named: "inputFactors")
            let given = factorArray?.value ?? []
            factors = given.count == count || given.isEmpty ? given : given.resampled(count: count)
        }
        self.outputTransforms.send(Self.blended(a, b, factors: factors))
    }
}
