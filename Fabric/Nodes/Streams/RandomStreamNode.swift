//
//  RandomStreamNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Random elements on the GPU, each between Minimum and Maximum. The same Seed gives the same
/// stream; Every Frame gives a new one each frame, for respawning particles somewhere new.
public final class RandomStreamNode: StrategyNode
{
    override public class var name: String { "Random Stream" }
    override public class var nodeType: Node.NodeType { .Streams }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Count random elements on the GPU, each component between Minimum and Maximum. The same Seed gives the same stream; Every Frame gives a new one each frame. Choose the element type in Settings." }

    override public class var strategyOptions: [any NodeStrategyOption] { [PortType.Float, PortType.Vector2, PortType.Vector3, PortType.Vector4] }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 1_000, .inputfield, "How many elements"))),
            ("inputSeed", ParameterPort(parameter: IntParameter("Seed", 0, .inputfield, "Which random stream: the same seed gives the same one"))),
            ("inputEveryFrame", ParameterPort(parameter: BoolParameter("Every Frame", false, .button, "Makes a new stream each frame"))),
        ]
    }

    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }
    public var inputSeed: ParameterPort<Int> { port(named: "inputSeed") }
    public var inputEveryFrame: ParameterPort<Bool> { port(named: "inputEveryFrame") }

    /// Every Frame runs it each frame, though no input changed.
    override public var isDirty: Bool { (inputEveryFrame.value ?? false) || super.isDirty }

    public var elementType: PortType { strategyOption(as: PortType.self) ?? .Float }

    private let operationKernel = StreamOperationKernel()
    /// The kernel compiled, so the next execution makes a stream whatever the inputs say.
    private var kernelChanged = true

    // Resolved when the element type changes, so execution looks up nothing.
    private var resolvedOutput: (any GPUStreamPort)?
    private var resolvedMinimum: Port?
    private var resolvedMaximum: Port?

    override public func rebuildPorts(forStrategy strategy: (any NodeStrategyOption)?)
    {
        super.rebuildPorts(forStrategy: strategy)
        guard let elementType = strategy as? PortType else { return }

        let existingMaximum: Port? = findPort(named: "inputMaximum")
        let keepsMaximum = existingMaximum?.portType == elementType

        addOrReplaceDynamicPortPreservingIdentity(name: "inputMinimum", displayName: "Minimum", portType: elementType,
                                                  kind: .Inlet, description: "The smallest each component can be")
        addOrReplaceDynamicPortPreservingIdentity(name: "inputMaximum", displayName: "Maximum", portType: elementType,
                                                  kind: .Inlet, description: "The largest each component can be")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputStream", displayName: "Random", portType: .Stream(elementType: elementType),
                                                  kind: .Outlet, description: "Count random elements")

        let portOrder = ["inputCount", "inputSeed", "inputEveryFrame", "inputMinimum", "inputMaximum", "outputStream"]
        let reordered: [Port] = portOrder.compactMap { name in let port: Port? = findPort(named: name); return port }
        if reordered.count == self.ports.count { reorderPorts(reordered) }

        let output: Port? = findPort(named: "outputStream")
        resolvedOutput = output as? any GPUStreamPort
        resolvedMinimum = findPort(named: "inputMinimum")
        resolvedMaximum = findPort(named: "inputMaximum")

        // A new Maximum starts at one, so a fresh node gives values in [0, 1).
        if !keepsMaximum
        {
            switch elementType
            {
            case .Vector2: resolvedMaximum?.restoreValue(from: .Vector2(.one))
            case .Vector3: resolvedMaximum?.restoreValue(from: .Vector3(.one))
            case .Vector4: resolvedMaximum?.restoreValue(from: .Vector4(.one))
            default: resolvedMaximum?.restoreValue(from: .Float(1))
            }
        }

        if executionState != .disabled { compileKernel() }
    }

    // MARK: Kernel

    private func compileKernel()
    {
        operationKernel.compile(source: Self.kernelSource(for: elementType), device: context.device)
        kernelChanged = true
        subtitleSubject.send()
    }

    override public func enableExecution(renderer: GraphRenderer) throws
    {
        compileKernel()
        try super.enableExecution(renderer: renderer)
    }

    override public func disableExecution(renderer: GraphRenderer) throws
    {
        operationKernel.release()
        try super.disableExecution(renderer: renderer)
    }

    override public func deriveStatuses() -> [NodeStatus] { operationKernel.failure.map { [NodeStatus.error($0)] } ?? [] }

    private struct RandomStreamUniforms
    {
        var count: UInt32
        var seed: UInt32
        var frame: UInt32
        var reserved: UInt32 = 0
        var minimum: simd_float4
        var maximum: simd_float4
    }

    static func kernelSource(for elementType: PortType) -> String
    {
        StreamOperationKernel.source(
            inputs: [],
            uniforms: """
            struct StreamOperationUniforms {
                uint count;
                uint seed;
                uint frame;
                uint reserved;
                float4 minimum;
                float4 maximum;
            };
            """,
            helpers: StreamOperationKernel.hashHelpers,
            outputType: elementType,
            body: """
                const uint key = fabricHash(id ^ fabricHash(uniforms.seed ^ fabricHash(uniforms.frame)));
                const float4 unit = float4(fabricUnit(key), fabricUnit(fabricHash(key + 1u)),
                                           fabricUnit(fabricHash(key + 2u)), fabricUnit(fabricHash(key + 3u)));
                value = \(StreamOperationKernel.constant("mix(uniforms.minimum, uniforms.maximum, unit)", as: elementType));
            """)
    }

    // MARK: Execute

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        let kernelJustChanged = kernelChanged
        kernelChanged = false
        let everyFrame = inputEveryFrame.value ?? false
        let inputsChanged = ports.contains { $0.kind == .Inlet && $0.valueDidChange }
        guard kernelJustChanged || inputsChanged || everyFrame, let output = resolvedOutput else { return }

        let count = min(max(inputCount.value ?? 0, 0), Int(UInt32.max))
        // Bit patterns, so a negative seed or a late frame still picks a stream.
        let seed = UInt32(truncatingIfNeeded: inputSeed.value ?? 0)
        let frame = everyFrame ? UInt32(truncatingIfNeeded: executionInfo.timing.frameNumber) : 0
        var uniforms = RandomStreamUniforms(count: UInt32(count), seed: seed, frame: frame,
                                            minimum: StreamOperationKernel.uniformVector(from: resolvedMinimum),
                                            maximum: StreamOperationKernel.uniformVector(from: resolvedMaximum))
        try operationKernel.encode(uniforms: &uniforms, inputs: [], count: .known(count), outputType: elementType, output: output,
                                   label: "Random Stream", commandBuffer: commandBuffer, allocator: context.gpuAllocator)
    }
}
