//
//  StreamToArrayNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Reads a stream back to the CPU as an array: the only node that does. It reads a stream the CPU can
/// see in place, copies a GPU-only one's valid elements (and a GPU-written count) into its own shared
/// buffer, and decodes once the GPU is done.
/// Same Frame waits for the GPU; Next Frame publishes on a later execution of this node and
/// Iterator scope once the copy has completed, which may be several frames later.
public final class StreamToArrayNode: StrategyNode
{
    override public class var name: String { "Stream to Array" }
    override public class var nodeType: Node.NodeType { .Streams }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Reads a stream back to the CPU as an array. Choose the element type in Settings. Same Frame waits for the GPU; Next Frame delivers later without waiting." }

    override public class var strategyOptions: [any NodeStrategyOption] { PortType.streamElementTypes }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputResultDelivery", ParameterPort(parameter: StringParameter(
                "Result Timing", GPUResultDeliveryMode.sync.rawValue,
                GPUResultDeliveryMode.allCases.map(\.rawValue), .dropdown,
                "Same Frame waits for GPU results; Next Frame publishes completed results on a later matching execution"))),
        ]
    }

    public var inputResultDelivery: ParameterPort<String> { port(named: "inputResultDelivery") }

    public var resultDeliveryMode: GPUResultDeliveryMode
    {
        get { GPUResultDeliveryMode(rawValue: inputResultDelivery.value ?? "") ?? .sync }
        set { inputResultDelivery.value = newValue.rawValue }
    }

    public var elementType: PortType { strategyOption(as: PortType.self) ?? .Float }

    private var previousDeliveryMode: GPUResultDeliveryMode?
    /// Copies bytes a blit can't: a GPU-only stream whose elements don't end on a 4-byte boundary.
    private let byteCopy = ComputeKernel()

    override public func rebuildPorts(forStrategy strategy: (any NodeStrategyOption)?)
    {
        super.rebuildPorts(forStrategy: strategy)
        guard let elementType = strategy as? PortType else { return }

        addOrReplaceDynamicPortPreservingIdentity(name: "inputStream", displayName: "Stream", portType: .Stream(elementType: elementType),
                                                  kind: .Inlet, description: "The stream to read back")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputArray", displayName: "Array", portType: .Array(portType: elementType),
                                                  kind: .Outlet, description: "The stream's valid elements")

        // A pending read decodes the old element type; drop it and read the current input again.
        cancelPendingCompletions()
        previousDeliveryMode = nil

        let portOrder = ["inputStream", "inputResultDelivery", "outputArray"]
        let reordered: [Port] = portOrder.compactMap { name in let port: Port? = findPort(named: name); return port }
        if reordered.count == self.ports.count { reorderPorts(reordered) }
    }

    /// Same Frame says it waits, since every change then stalls the frame on the GPU.
    override public func deriveStatuses() -> [NodeStatus]
    {
        resultDeliveryMode == .sync ? [.warning("Same Frame waits for the GPU each time the stream changes")] : []
    }

    override public func enableExecution(renderer: GraphRenderer) throws
    {
        byteCopy.compile(source: Self.byteCopySource, functionNames: ["streamReadbackCopyKernel"], device: context.device)
        try super.enableExecution(renderer: renderer)
    }

    override public func disableExecution(renderer: GraphRenderer) throws
    {
        byteCopy.release()
        try super.disableExecution(renderer: renderer)
    }

    override public func stopExecution(renderer: GraphRenderer) throws
    {
        previousDeliveryMode = nil
        try super.stopExecution(renderer: renderer)
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        switch elementType
        {
        case .Float:      try readBack(Float.self, renderer: renderer, commandBuffer: commandBuffer)
        case .Int:        try readBack(Int.self, renderer: renderer, commandBuffer: commandBuffer)
        case .Vector2:    try readBack(simd_float2.self, renderer: renderer, commandBuffer: commandBuffer)
        case .Vector3:    try readBack(simd_float3.self, renderer: renderer, commandBuffer: commandBuffer)
        case .Vector4:    try readBack(simd_float4.self, renderer: renderer, commandBuffer: commandBuffer)
        case .Quaternion: try readBack(simd_quatf.self, renderer: renderer, commandBuffer: commandBuffer)
        default:          return
        }
    }

    private func readBack<Element: GPUStreamElement>(_: Element.Type, renderer: GraphRenderer, commandBuffer: MTLCommandBuffer) throws
    {
        guard let input = findPort(named: "inputStream") as NodePort<GPUStream<Element>>?,
              let output = findPort(named: "outputArray") as NodePort<ContiguousArray<Element>>?
        else { return }

        let mode = resultDeliveryMode
        let modeChanged = previousDeliveryMode != mode
        if modeChanged
        {
            cancelPendingCompletions()
            previousDeliveryMode = mode
            subtitleSubject.send()
        }

        guard let stream = input.value else
        {
            cancelPendingCompletions()
            output.send(nil)
            return
        }

        // A mode change reads the current input again, even when it hasn't changed.
        guard modeChanged || input.valueDidChange else { return }

        let layout = stream.attribute.layout
        let capacity = stream.count.capacity
        guard capacity > 0 else
        {
            cancelPendingCompletions()
            output.send([], force: true)
            return
        }

        // Delivery reads storage nothing else writes: the stream's own buffer when the CPU can read
        // it, since a published attribute never changes, or else a copy; and a copy of a GPU count.
        let elementBytes = (capacity - 1) * layout.byteStride + layout.elementSize
        let source = stream.attribute.buffer
        let copiesElements = source.storageMode != .shared
        // A blit copies 4-byte multiples from 4-byte offsets, so it takes the aligned bytes around
        // the elements when the buffer has them; the byte-copy kernel takes exactly the elements.
        let alignedStart = layout.byteOffset / 4 * 4
        let alignedEnd = Self.roundedUpToFour(layout.byteOffset + elementBytes)
        let blitsElements = copiesElements && alignedEnd <= source.length
        let copyStart = blitsElements ? alignedStart : layout.byteOffset
        let copyLength = blitsElements ? alignedEnd - alignedStart : elementBytes
        let countOffset = copiesElements ? Self.roundedUpToFour(copyLength) : 0
        let readback = try context.gpuAllocator.makeBuffer(length: countOffset + MemoryLayout<UInt32>.stride,
                                                           memoryClass: .cpuReads,
                                                           label: "Stream Readback")

        if copiesElements && !blitsElements
        {
            guard let pipeline = byteCopy.pipelines?.first, let compute = commandBuffer.makeComputeCommandEncoder() else
            {
                throw FabricError(.execution(.gpu), severity: .recoverable, message: "Unable to encode the stream readback")
            }
            var range = simd_uint2(UInt32(copyStart), UInt32(copyLength))
            compute.label = "Stream Readback Copy"
            compute.setBuffer(source, offset: 0, index: 0)
            compute.setBuffer(readback, offset: 0, index: 1)
            compute.setBytes(&range, length: MemoryLayout<simd_uint2>.stride, index: 2)
            BaseGPUPointsNode.dispatchPerPoint(compute, pipeline: pipeline, count: copyLength)
            compute.endEncoding()
        }

        let countArguments: PointsDrawArguments?
        if case let .gpu(arguments, _) = stream.count { countArguments = arguments } else { countArguments = nil }
        if blitsElements || countArguments != nil
        {
            guard let blit = commandBuffer.makeBlitCommandEncoder() else
            {
                throw FabricError(.execution(.gpu), severity: .recoverable, message: "Unable to encode the stream readback")
            }
            if blitsElements
            {
                blit.copy(from: source, sourceOffset: copyStart, to: readback, destinationOffset: 0, size: copyLength)
            }
            if let countArguments
            {
                blit.copy(from: countArguments.buffer, sourceOffset: countArguments.offset, to: readback,
                          destinationOffset: countOffset, size: MemoryLayout<UInt32>.stride)
            }
            blit.endEncoding()
        }

        let elements = copiesElements ? readback : source
        let elementsLayout = AttributeLayout(scalar: layout.scalar, components: layout.components,
                                             byteOffset: copiesElements ? layout.byteOffset - copyStart : layout.byteOffset,
                                             byteStride: layout.byteStride)
        let count = stream.count
        let deliver = {
            let validCount: Int
            switch count
            {
            case .known(let known):
                validCount = known
            case .gpu(_, let capacity):
                validCount = min(Int(readback.contents().load(fromByteOffset: countOffset, as: UInt32.self)), capacity)
            }
            output.send(Element.readStream(elements.contents(), layout: elementsLayout, count: validCount), force: true)
        }

        if mode == .sync
        {
            try renderer.waitForGPUResults(commandBuffer: commandBuffer)
            deliver()
        }
        else
        {
            try commandBuffer.addCompletion(deliver)
        }
    }

    private static func roundedUpToFour(_ bytes: Int) -> Int
    {
        (bytes + 3) / 4 * 4
    }

    private static let byteCopySource = """
    #include <metal_stdlib>
    using namespace metal;

    // range.x is the first byte to copy, range.y how many.
    kernel void streamReadbackCopyKernel(device const uchar *source [[buffer(0)]],
                                         device uchar *destination [[buffer(1)]],
                                         constant uint2 &range [[buffer(2)]],
                                         uint id [[thread_position_in_grid]]) {
        if (id >= range.y) { return; }
        destination[id] = source[range.x + id];
    }
    """
}
