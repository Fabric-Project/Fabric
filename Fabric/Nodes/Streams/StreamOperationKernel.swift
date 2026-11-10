//
//  StreamOperationKernel.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// A compute kernel that writes one output stream, one element per thread, from the streams it reads:
/// what Stream Math, Stream Select, Random Stream, Stream Noise and Stream Ramp run. Its kernel takes
/// the node's uniforms at buffer 0, the output at buffer 1, and the inputs from buffer 2, as
/// `source` lays them out. The node compiles it when it is enabled or its element type changes,
/// never from `execute`.
final class StreamOperationKernel
{
    private static let functionName = "streamOperationKernel"

    private let kernel = ComputeKernel()
    /// Binds a missing input with no elements.
    private var placeholder: MTLBuffer?
    /// Scratch kept across executions, so binding allocates nothing once it has grown.
    private var layoutScratch = ContiguousArray<StreamKernel.Layout>()
    /// The empty stream last sent, kept so an empty input sends the same one each frame.
    private var emptyAttribute: PublishedAttribute?

    /// What the last compile reported, or nil when it compiled.
    var failure: String? { kernel.failure }

    func compile(source: String, device: MTLDevice)
    {
        kernel.compile(source: source, functionNames: [Self.functionName], device: device)
        if placeholder == nil { placeholder = device.makeBuffer(length: 16, options: .storageModeShared) }
    }

    /// Drops the compiled kernel, for a node that is disabled.
    func release()
    {
        kernel.release()
    }

    /// Writes `count` elements of `outputType` into a new buffer and sends it on `output` with that
    /// count, a GPU-written one included. With no elements it sends an empty stream and dispatches
    /// nothing; with no compiled kernel, `output` is cleared.
    func encode<Uniforms>(uniforms: inout Uniforms,
                          inputs: [(any GPUStreamPort)?],
                          count: GPUStreamCount,
                          outputType: PortType,
                          output: any GPUStreamPort,
                          label: String,
                          commandBuffer: MTLCommandBuffer,
                          allocator: GPUAllocator) throws
    {
        guard let pipeline = kernel.pipelines?.first, let placeholder else
        {
            output.clearStream()
            return
        }

        let storage = StreamKernel.outputStorage(outputType)
        let layout = AttributeLayout(scalar: storage.scalar, components: storage.components, byteOffset: 0, byteStride: storage.byteStride)

        // Empty is a stream, not a missing one: send one with no elements, the same each time.
        guard count.capacity > 0 else
        {
            if emptyAttribute?.layout != layout
            {
                emptyAttribute = PublishedAttribute(adopting: placeholder, layout: layout, count: 0)
            }
            if let emptyAttribute { try output.sendStream(attribute: emptyAttribute, count: count) }
            return
        }

        let buffer = try allocator.makeBuffer(length: count.capacity * storage.byteStride, memoryClass: .gpuOnly, label: label)

        // A fresh buffer holds nothing until the kernel runs, so with no encoder nothing is published.
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Unable to encode \(label)")
        }
        encoder.label = label
        encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setBuffer(buffer, offset: 0, index: 1)
        StreamKernel.bind(inputs, encoder: encoder, firstBuffer: 2, placeholder: placeholder, layouts: &layoutScratch)
        BaseGPUPointsNode.dispatchPerPoint(encoder, pipeline: pipeline, count: count.capacity)
        encoder.endEncoding()

        try output.sendStream(attribute: PublishedAttribute(adopting: buffer, layout: layout, count: count.capacity), count: count)
    }

    // MARK: Source

    /// A kernel that reads `inputs` as `inputs.<name>`, takes `uniforms` (a Metal struct named
    /// `StreamOperationUniforms` whose first member is `uint count`), runs `body` for each element
    /// below that count, and stores the `value` it assigns, of `outputType`'s Metal type.
    static func source(inputs: [StreamKernelField], uniforms: String, helpers: String, outputType: PortType, body: String) -> String
    {
        let storage = StreamKernel.outputStorage(outputType)
        return """
        #include <metal_stdlib>
        using namespace metal;

        \(StreamKernel.preamble)

        \(StreamKernel.inputsStruct(named: "StreamOperationInputs", fields: inputs))

        \(uniforms)

        \(operandHelper)

        \(helpers)

        kernel void \(functionName)(constant StreamOperationUniforms &uniforms [[buffer(0)]],
            device \(storage.bufferType) *result [[buffer(1)]],
        \(StreamKernel.inputParameters(inputs, firstBuffer: 2))
            uint id [[thread_position_in_grid]]) {
        \(StreamKernel.inputsInitializer(structName: "StreamOperationInputs", fields: inputs))
            if (id >= uniforms.count) { return; }
            \(StreamKernel.metalType(outputType)) value;
        \(body)
            result[id] = \(storage.store("value"));
        }
        """
    }

    /// `fabricOperand(stream, id, constant)`: the stream's element `id` when it has elements, its last
    /// element past its end, so a one-element stream applies to every element, and `constant` when
    /// it has none, which is how an unwired stream input falls back to its value.
    private static let operandHelper = """
    template <typename Stream, typename Value>
    Value fabricOperand(thread const Stream &stream, uint id, Value constantValue) {
        const uint count = stream.count();
        return count > 0 ? Value(stream.read(min(id, count - 1))) : constantValue;
    }
    """

    /// `fabricHash(v)`, a PCG hash, and `fabricUnit(v)`, a hash as a float in [0, 1). Integer, so
    /// every index of a long stream gets its own value, where Lygia's float hashes repeat past 2²⁴.
    static let hashHelpers = """
    uint fabricHash(uint v) {
        const uint state = v * 747796405u + 2891336453u;
        const uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
        return (word >> 22u) ^ word;
    }

    float fabricUnit(uint v) {
        return float(v >> 8) * (1.0 / 16777216.0);
    }
    """

    /// Lygia's `path`, such as `generative/curl.msl`, with its includes inlined, from the copy
    /// Fabric ships; nil when it can't be read. Kernels take noise from here, as Fabric's image
    /// generators do, so a field means the same thing wherever it is sampled.
    static func lygiaSource(_ path: String) -> String?
    {
        guard let url = Bundle.module.resourceURL?.appending(path: "lygia").appending(path: path) else { return nil }
        return try? MetalFileCompiler(watch: false).parse(url)
    }

    /// `expression`, a `float4` uniform, as a value of `elementType`'s Metal type.
    static func constant(_ expression: String, as elementType: PortType) -> String
    {
        switch elementType
        {
        case .Int: return "int((\(expression)).x)"
        case .Vector2: return "(\(expression)).xy"
        case .Vector3: return "(\(expression)).xyz"
        case .Vector4, .Quaternion: return "(\(expression))"
        default: return "(\(expression)).x"
        }
    }

    /// The value `port` holds, as the `float4` a uniform carries: a scalar in x, a vector from x.
    static func uniformVector(from port: Port?) -> simd_float4
    {
        switch port?.snapshotValue()
        {
        case .Float(let value): return simd_float4(value, 0, 0, 0)
        case .Int(let value): return simd_float4(Float(value), 0, 0, 0)
        case .Vector2(let value): return simd_float4(value.x, value.y, 0, 0)
        case .Vector3(let value): return simd_float4(value, 0)
        case .Vector4(let value): return value
        case .Quaternion(let value): return value.vector
        default: return .zero
        }
    }
}
