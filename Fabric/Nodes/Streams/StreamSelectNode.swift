//
//  StreamSelectNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Picks each element from A or B by a condition stream on the GPU: A where Condition is above
/// Threshold, B elsewhere. With Stream Feedback it respawns: keep a particle's position while its
/// life is above zero, take a fresh one where it isn't.
public final class StreamSelectNode: StrategyNode
{
    override public class var name: String { "Stream Select" }
    override public class var nodeType: Node.NodeType { .Streams }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Picks each element from A where Condition is above Threshold, and from B elsewhere, one element per element of Condition. A shorter stream repeats its last element; an unwired one gives zero. Choose the element type in Settings." }

    override public class var strategyOptions: [any NodeStrategyOption] { PortType.streamElementTypes }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCondition", NodePort<GPUStream<Float>>(name: "Condition", kind: .Inlet, description: "Picks A where it is above Threshold")),
            ("inputThreshold", ParameterPort(parameter: FloatParameter("Threshold", 0, .inputfield, "Condition above this picks A"))),
        ]
    }

    public var inputCondition: NodePort<GPUStream<Float>> { port(named: "inputCondition") }
    public var inputThreshold: ParameterPort<Float> { port(named: "inputThreshold") }

    public var elementType: PortType { strategyOption(as: PortType.self) ?? .Float }

    private let operationKernel = StreamOperationKernel()
    /// The kernel compiled, so the next execution picks whatever the inputs say.
    private var kernelChanged = true

    // Resolved when the element type changes, so execution looks up nothing.
    private var resolvedInputs: [(any GPUStreamPort)?] = []
    private var resolvedOutput: (any GPUStreamPort)?

    override public func rebuildPorts(forStrategy strategy: (any NodeStrategyOption)?)
    {
        super.rebuildPorts(forStrategy: strategy)
        guard let elementType = strategy as? PortType else { return }

        let streamType = PortType.Stream(elementType: elementType)
        addOrReplaceDynamicPortPreservingIdentity(name: "inputA", displayName: "A", portType: streamType,
                                                  kind: .Inlet, description: "Picked where Condition is above Threshold")
        addOrReplaceDynamicPortPreservingIdentity(name: "inputB", displayName: "B", portType: streamType,
                                                  kind: .Inlet, description: "Picked elsewhere")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputStream", displayName: "Result", portType: streamType,
                                                  kind: .Outlet, description: "One element per element of Condition")

        let portOrder = ["inputCondition", "inputThreshold", "inputA", "inputB", "outputStream"]
        let reordered: [Port] = portOrder.compactMap { name in let port: Port? = findPort(named: name); return port }
        if reordered.count == self.ports.count { reorderPorts(reordered) }

        resolvedInputs = ["inputCondition", "inputA", "inputB"].map { name in let port: Port? = findPort(named: name); return port as? any GPUStreamPort }
        let output: Port? = findPort(named: "outputStream")
        resolvedOutput = output as? any GPUStreamPort

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

    private struct StreamSelectUniforms
    {
        var count: UInt32
        var threshold: Float
        var reserved0: UInt32 = 0
        var reserved1: UInt32 = 0
    }

    static func kernelSource(for elementType: PortType) -> String
    {
        let type = StreamKernel.metalType(elementType)
        let zero = StreamKernel.outputStorage(elementType).defaultValue
        return StreamOperationKernel.source(
            inputs: [StreamKernelField(name: "condition", elementType: .Float),
                     StreamKernelField(name: "a", elementType: elementType),
                     StreamKernelField(name: "b", elementType: elementType)],
            uniforms: """
            struct StreamOperationUniforms {
                uint count;
                float threshold;
                uint reserved0;
                uint reserved1;
            };
            """,
            helpers: "",
            outputType: elementType,
            body: """
                const \(type) zero = \(zero);
                value = inputs.condition.read(id) > uniforms.threshold ? fabricOperand(inputs.a, id, zero) : fabricOperand(inputs.b, id, zero);
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
        let inputsChanged = ports.contains { $0.kind == .Inlet && $0.valueDidChange }
        guard kernelJustChanged || inputsChanged, let output = resolvedOutput else { return }

        guard let count = inputCondition.value?.count else
        {
            output.clearStream()
            return
        }

        var uniforms = StreamSelectUniforms(count: UInt32(count.capacity), threshold: inputThreshold.value ?? 0)
        try operationKernel.encode(uniforms: &uniforms, inputs: resolvedInputs, count: count, outputType: elementType, output: output,
                                   label: "Stream Select", commandBuffer: commandBuffer, allocator: context.gpuAllocator)
    }
}
