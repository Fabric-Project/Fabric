//
//  StreamRampNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Colors each element of a float stream on the GPU by where it falls between Minimum and Maximum:
/// Start Color at Minimum to End Color at Maximum, such as a particle fading as its life runs out.
public final class StreamRampNode: Node
{
    override public class var name: String { "Stream Ramp" }
    override public class var nodeType: Node.NodeType { .Streams }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Maps each value to a color on the GPU: Start Color at Minimum, End Color at Maximum, and blends between them, clamped outside." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputValues", NodePort<GPUStream<Float>>(name: "Values", kind: .Inlet, description: "The values to color")),
            ("inputMinimum", ParameterPort(parameter: FloatParameter("Minimum", 0, .inputfield, "The value colored Start Color"))),
            ("inputMaximum", ParameterPort(parameter: FloatParameter("Maximum", 1, .inputfield, "The value colored End Color"))),
            ("inputStartColor", ParameterPort(parameter: Float4Parameter("Start Color", simd_float4(0, 0, 0, 0), .zero, .one, .colorpicker, "The color at Minimum and below"))),
            ("inputEndColor", ParameterPort(parameter: Float4Parameter("End Color", .one, .zero, .one, .colorpicker, "The color at Maximum and above"))),
            ("outputColors", NodePort<GPUStream<simd_float4>>(name: "Colors", kind: .Outlet, description: "One color per value")),
        ]
    }

    public var inputValues: NodePort<GPUStream<Float>> { port(named: "inputValues") }
    public var inputMinimum: ParameterPort<Float> { port(named: "inputMinimum") }
    public var inputMaximum: ParameterPort<Float> { port(named: "inputMaximum") }
    public var inputStartColor: ParameterPort<simd_float4> { port(named: "inputStartColor") }
    public var inputEndColor: ParameterPort<simd_float4> { port(named: "inputEndColor") }
    public var outputColors: NodePort<GPUStream<simd_float4>> { port(named: "outputColors") }

    private let operationKernel = StreamOperationKernel()
    /// The kernel compiled, so the next execution colors whatever the inputs say.
    private var kernelChanged = true

    override public func enableExecution(renderer: GraphRenderer) throws
    {
        operationKernel.compile(source: Self.kernelSource, device: context.device)
        kernelChanged = true
        subtitleSubject.send()
        try super.enableExecution(renderer: renderer)
    }

    override public func disableExecution(renderer: GraphRenderer) throws
    {
        operationKernel.release()
        try super.disableExecution(renderer: renderer)
    }

    override public func deriveStatuses() -> [NodeStatus] { operationKernel.failure.map { [NodeStatus.error($0)] } ?? [] }

    private struct StreamRampUniforms
    {
        var count: UInt32
        var reserved: UInt32 = 0
        var minimum: Float
        var maximum: Float
        var startColor: simd_float4
        var endColor: simd_float4
    }

    private static let kernelSource = StreamOperationKernel.source(
        inputs: [StreamKernelField(name: "values", elementType: .Float)],
        uniforms: """
        struct StreamOperationUniforms {
            uint count;
            uint reserved;
            float minimum;
            float maximum;
            float4 startColor;
            float4 endColor;
        };
        """,
        helpers: "",
        outputType: .Vector4,
        body: """
            // Equal ends make a step at that value.
            const float span = uniforms.maximum - uniforms.minimum;
            const float v = inputs.values.read(id);
            const float t = span != 0.0 ? saturate((v - uniforms.minimum) / span) : (v >= uniforms.maximum ? 1.0 : 0.0);
            value = mix(uniforms.startColor, uniforms.endColor, t);
        """)

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        let kernelJustChanged = kernelChanged
        kernelChanged = false
        let inputsChanged = ports.contains { $0.kind == .Inlet && $0.valueDidChange }
        guard kernelJustChanged || inputsChanged else { return }

        guard let count = inputValues.value?.count else
        {
            outputColors.send(nil)
            return
        }

        var uniforms = StreamRampUniforms(count: UInt32(count.capacity),
                                          minimum: inputMinimum.value ?? 0,
                                          maximum: inputMaximum.value ?? 1,
                                          startColor: inputStartColor.value ?? .zero,
                                          endColor: inputEndColor.value ?? .one)
        try operationKernel.encode(uniforms: &uniforms, inputs: [inputValues], count: count, outputType: .Vector4, output: outputColors,
                                   label: "Stream Ramp", commandBuffer: commandBuffer, allocator: context.gpuAllocator)
    }
}
