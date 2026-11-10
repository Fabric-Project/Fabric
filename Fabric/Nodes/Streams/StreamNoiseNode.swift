//
//  StreamNoiseNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Lygia's simplex noise sampled at each position on the GPU, moving over time: a force for
/// particles. Curl noise swirls without bunching up, since it has no sources or sinks.
public final class StreamNoiseNode: Node
{
    override public class var name: String { "Stream Noise" }
    override public class var nodeType: Node.NodeType { .Streams }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Samples Lygia's simplex noise at each position on the GPU, one vector per position, moving at Speed over time. Curl swirls without bunching up, for particle forces." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputPositions", NodePort<GPUStream<simd_float3>>(name: "Positions", kind: .Inlet, description: "Where to sample the field")),
            ("inputFrequency", ParameterPort(parameter: FloatParameter("Frequency", 1, .inputfield, "How many features per unit: higher is finer"))),
            ("inputAmplitude", ParameterPort(parameter: FloatParameter("Amplitude", 1, .inputfield, "How strong the field is"))),
            ("inputSpeed", ParameterPort(parameter: FloatParameter("Speed", 0.25, .inputfield, "How fast the field moves, per second"))),
            ("inputCurl", ParameterPort(parameter: BoolParameter("Curl", true, .toggle, "Swirls without bunching up, rather than plain noise"))),
            ("outputNoise", NodePort<GPUStream<simd_float3>>(name: "Noise", kind: .Outlet, description: "One vector per position")),
        ]
    }

    public var inputPositions: NodePort<GPUStream<simd_float3>> { port(named: "inputPositions") }
    public var inputFrequency: ParameterPort<Float> { port(named: "inputFrequency") }
    public var inputAmplitude: ParameterPort<Float> { port(named: "inputAmplitude") }
    public var inputSpeed: ParameterPort<Float> { port(named: "inputSpeed") }
    public var inputCurl: ParameterPort<Bool> { port(named: "inputCurl") }
    public var outputNoise: NodePort<GPUStream<simd_float3>> { port(named: "outputNoise") }

    /// A moving field runs each frame, though no input changed.
    override public var isDirty: Bool { (inputSpeed.value ?? 0) != 0 || super.isDirty }

    private let operationKernel = StreamOperationKernel()

    override public func enableExecution(renderer: GraphRenderer) throws
    {
        operationKernel.compile(source: Self.kernelSource, device: context.device)
        subtitleSubject.send()
        try super.enableExecution(renderer: renderer)
    }

    override public func disableExecution(renderer: GraphRenderer) throws
    {
        operationKernel.release()
        try super.disableExecution(renderer: renderer)
    }

    override public func deriveStatuses() -> [NodeStatus] { operationKernel.failure.map { [NodeStatus.error($0)] } ?? [] }

    private struct StreamNoiseUniforms
    {
        var count: UInt32
        var curl: UInt32
        var time: Float
        var frequency: Float
        var amplitude: Float
        var reserved0: Float = 0
        var reserved1: Float = 0
        var reserved2: Float = 0
    }

    /// Lygia's simplex noise and curl noise, sampled in four dimensions so time moves the field
    /// smoothly rather than sliding it.
    private static let kernelSource = StreamOperationKernel.source(
        inputs: [StreamKernelField(name: "positions", elementType: .Vector3)],
        uniforms: """
        struct StreamOperationUniforms {
            uint count;
            uint curl;
            float time;
            float frequency;
            float amplitude;
            float reserved0;
            float reserved1;
            float reserved2;
        };
        """,
        helpers: StreamOperationKernel.lygiaSource("generative/curl.msl") ?? "",
        outputType: .Vector3,
        body: """
            const float4 p = float4(inputs.positions.read(id) * uniforms.frequency, uniforms.time);
            value = uniforms.amplitude * (uniforms.curl != 0 ? curl(p) : snoise3(p));
        """)

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        guard let count = inputPositions.value?.count else
        {
            outputNoise.send(nil)
            return
        }

        let speed = inputSpeed.value ?? 0
        // A still field changes only with its inputs.
        let inputsChanged = ports.contains { $0.kind == .Inlet && $0.valueDidChange }
        guard inputsChanged || speed != 0 || outputNoise.value == nil else { return }

        var uniforms = StreamNoiseUniforms(count: UInt32(count.capacity),
                                           curl: (inputCurl.value ?? true) ? 1 : 0,
                                           time: Float(executionInfo.timing.time) * speed,
                                           frequency: inputFrequency.value ?? 1,
                                           amplitude: inputAmplitude.value ?? 1)
        try operationKernel.encode(uniforms: &uniforms, inputs: [inputPositions], count: count, outputType: .Vector3, output: outputNoise,
                                   label: "Stream Noise", commandBuffer: commandBuffer, allocator: context.gpuAllocator)
    }
}
