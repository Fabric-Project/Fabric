//
//  ArrayToStreamNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Copies an array to the GPU as a stream of the same element type. Each change publishes a new
/// buffer, so a stream already sent never changes.
public final class ArrayToStreamNode: StrategyNode
{
    override public class var name: String { "Array to Stream" }
    override public class var nodeType: Node.NodeType { .Streams }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Copies an array to the GPU as a stream. Choose the element type in Settings; Int values outside the 32-bit range are clamped." }

    override public class var strategyOptions: [any NodeStrategyOption] { PortType.streamElementTypes }

    public var elementType: PortType { strategyOption(as: PortType.self) ?? .Float }

    private var clampedValues = false

    override public func rebuildPorts(forStrategy strategy: (any NodeStrategyOption)?)
    {
        super.rebuildPorts(forStrategy: strategy)
        guard let elementType = strategy as? PortType else { return }

        addOrReplaceDynamicPortPreservingIdentity(name: "inputArray", displayName: "Array", portType: .Array(portType: elementType),
                                                  kind: .Inlet, description: "The values to copy to the GPU")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputStream", displayName: "Stream", portType: .Stream(elementType: elementType),
                                                  kind: .Outlet, description: "The values as a stream")
        setClampedValues(false)
    }

    override public func deriveStatuses() -> [NodeStatus]
    {
        clampedValues ? [.warning("Some values were outside the 32-bit integer range and were clamped")] : []
    }

    private func setClampedValues(_ clamped: Bool)
    {
        guard clamped != clampedValues else { return }
        clampedValues = clamped
        subtitleSubject.send()
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        switch elementType
        {
        case .Float:      try publish(Float.self)
        case .Int:        try publish(Int.self)
        case .Vector2:    try publish(simd_float2.self)
        case .Vector3:    try publish(simd_float3.self)
        case .Vector4:    try publish(simd_float4.self)
        case .Quaternion: try publish(simd_quatf.self)
        default:          return
        }
    }

    private func publish<Element: GPUStreamElement>(_: Element.Type) throws
    {
        guard let input = findPort(named: "inputArray") as NodePort<ContiguousArray<Element>>?,
              let output = findPort(named: "outputStream") as NodePort<GPUStream<Element>>?,
              input.valueDidChange
        else { return }

        guard let values = input.value else
        {
            setClampedValues(false)
            output.send(nil)
            return
        }

        let published = try Element.publishStream(values, allocator: context.gpuAllocator)
        setClampedValues(published.clamped)
        output.send(try GPUStream(attribute: published.attribute), force: true)
    }
}
