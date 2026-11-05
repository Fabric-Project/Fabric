//
//  ValueBlendNode.swift
//  Fabric
//

import Metal
import Satin
import simd

/// The manually driven analog of Tween: blends Source toward Target by Blend Amount using
/// Satin's `Lerpable`, so orientations slerp and Transforms decompose instead of skewing.
public final class ValueBlendNode: NumericTypeAgnosticNode
{
    public override class var name: String { "Value Blend" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Numeric) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Blends Source toward Target by Blend Amount: 0 is Source, 1 is Target, and values outside 0-1 extrapolate. Orientations slerp and Transforms blend as translation, rotation and scale. Arrays blend per element, as long as the shorter input. Choose the value type in Settings." }
    public override class var supportedPortTypes: [PortType] { interpolatableSingleTypes + interpolatableArrayTypes }

    public let inputBlendAmount = ParameterPort(parameter: FloatParameter("Blend Amount", 0.5, .inputfield, "0 is Source, 1 is Target; not clamped"))

    override public func bindPorts()
    {
        super.bindPorts()
        self.boundInputSource = findPort(named: "inputSource")
        self.boundInputTarget = findPort(named: "inputTarget")
        self.boundOutputValue = findPort(named: "outputValue")
    }

    public override func declaredPorts() -> [PortDeclaration]
    {
        let portType = selectedNumericPortType

        return [
            PortDeclaration(key: "inputSource", portType: portType, kind: .Inlet, name: "Source", description: "The value at Blend Amount 0"),
            PortDeclaration(key: "inputTarget", portType: portType, kind: .Inlet, name: "Target", description: "The value at Blend Amount 1"),
        ] + super.declaredPorts() + [
            PortDeclaration(key: "inputBlendAmount", port: self.inputBlendAmount),
            PortDeclaration(key: "outputValue", portType: portType, kind: .Outlet, name: "Value", description: "The blended value"),
        ]
    }

    /// `source` and `target` blended by `amount` with Satin's `Lerpable`; nil when their
    /// cases differ or are not blendable. Color travels as `.Vector4`, so it mixes per channel.
    public static func blended(_ source: PortValue, _ target: PortValue, amount: Float) -> PortValue?
    {
        switch (source, target)
        {
        case (.Float(let from), .Float(let to)):
            return .Float(.lerp(from, to, amount))
        case (.Vector2(let from), .Vector2(let to)):
            return .Vector2(.lerp(from, to, amount))
        case (.Vector3(let from), .Vector3(let to)):
            return .Vector3(.lerp(from, to, amount))
        case (.Vector4(let from), .Vector4(let to)):
            return .Vector4(.lerp(from, to, amount))
        case (.Quaternion(let from), .Quaternion(let to)):
            return .Quaternion(.lerp(from, to, amount))
        case (.Transform(let from), .Transform(let to)):
            return .Transform(.lerp(from, to, amount))
        case (.Array(let from), .Array(let to)):
            let count = min(from.count, to.count)
            var output = ContiguousArray<PortValue>()
            output.reserveCapacity(count)
            for index in 0..<count
            {
                if let value = blended(from[index], to[index], amount: amount)
                {
                    output.append(value)
                }
            }
            return .Array(output)
        default:
            return nil
        }
    }

    private var boundInputSource: Port?
    private var boundInputTarget: Port?
    private var boundOutputValue: Port?

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let inputSource: Port = self.boundInputSource,
              let inputTarget: Port = self.boundInputTarget,
              let outputValue: Port = self.boundOutputValue,
              inputSource.valueDidChange || inputTarget.valueDidChange || inputBlendAmount.valueDidChange,
              let source = inputSource.snapshotValue(),
              let target = inputTarget.snapshotValue(),
              let amount = inputBlendAmount.value
        else { return }

        outputValue.sendBoxed(Self.blended(source, target, amount: amount.isFinite ? amount : 0))
    }
}
