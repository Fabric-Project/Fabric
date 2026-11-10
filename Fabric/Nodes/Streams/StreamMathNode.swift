//
//  StreamMathNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// What Stream Math computes for each element, from A, B and C.
public enum StreamMathOperation: String, CaseIterable
{
    case add = "Add"
    case subtract = "Subtract"
    case multiply = "Multiply"
    case divide = "Divide"
    case multiplyAdd = "Multiply Add"
    case mix = "Mix"
    case minimum = "Minimum"
    case maximum = "Maximum"

    /// The operation's number in the kernel's switch.
    var kernelIndex: UInt32 { UInt32(Self.allCases.firstIndex(of: self) ?? 0) }
}

/// Elementwise math on streams on the GPU: A with B, and C where the operation takes it. B and C are
/// each a stream or, unwired, a value; a stream shorter than A repeats its last element.
public final class StreamMathNode: StrategyNode
{
    override public class var name: String { "Stream Math" }
    override public class var nodeType: Node.NodeType { .Streams }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Elementwise math on streams on the GPU, one element of Result per element of A. B and C are streams or, unwired, their values; a shorter stream repeats its last element. Multiply Add is A + B × C and Mix blends A to B by C. Choose the element type in Settings." }

    override public class var strategyOptions: [any NodeStrategyOption] { [PortType.Float, PortType.Vector2, PortType.Vector3, PortType.Vector4] }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputOperation", ParameterPort(parameter: StringParameter("Operation", StreamMathOperation.add.rawValue,
                                                                        StreamMathOperation.allCases.map(\.rawValue), .dropdown,
                                                                        "What to compute for each element"))),
        ]
    }

    public var inputOperation: ParameterPort<String> { port(named: "inputOperation") }

    public var operation: StreamMathOperation
    {
        get { StreamMathOperation(rawValue: inputOperation.value ?? "") ?? .add }
        set { inputOperation.value = newValue.rawValue }
    }

    public var elementType: PortType { strategyOption(as: PortType.self) ?? .Float }

    private let operationKernel = StreamOperationKernel()
    /// The kernel compiled, so the next execution computes whatever the inputs say.
    private var kernelChanged = true

    // Resolved when the element type changes, so execution looks up nothing.
    private var resolvedInputs: [(any GPUStreamPort)?] = []
    private var resolvedOutput: (any GPUStreamPort)?
    private var resolvedBValue: Port?
    private var resolvedCValue: Port?

    private static let streamFields = ["a", "b", "c"]

    override public func rebuildPorts(forStrategy strategy: (any NodeStrategyOption)?)
    {
        super.rebuildPorts(forStrategy: strategy)
        guard let elementType = strategy as? PortType else { return }

        let streamType = PortType.Stream(elementType: elementType)
        addOrReplaceDynamicPortPreservingIdentity(name: "inputA", displayName: "A", portType: streamType,
                                                  kind: .Inlet, description: "The stream to compute from, one Result element per element")
        addOrReplaceDynamicPortPreservingIdentity(name: "inputB", displayName: "B", portType: streamType,
                                                  kind: .Inlet, description: "The second operand; unwired, B Value")
        addOrReplaceDynamicPortPreservingIdentity(name: "inputBValue", displayName: "B Value", portType: elementType,
                                                  kind: .Inlet, description: "B for every element while B is unwired")
        addOrReplaceDynamicPortPreservingIdentity(name: "inputC", displayName: "C", portType: streamType,
                                                  kind: .Inlet, description: "Multiply Add's multiplier of B, or Mix's blend; unwired, C Value")
        addOrReplaceDynamicPortPreservingIdentity(name: "inputCValue", displayName: "C Value", portType: elementType,
                                                  kind: .Inlet, description: "C for every element while C is unwired")
        addOrReplaceDynamicPortPreservingIdentity(name: "outputStream", displayName: "Result", portType: streamType,
                                                  kind: .Outlet, description: "One element per element of A")

        let portOrder = ["inputOperation", "inputA", "inputB", "inputBValue", "inputC", "inputCValue", "outputStream"]
        let reordered: [Port] = portOrder.compactMap { name in let port: Port? = findPort(named: name); return port }
        if reordered.count == self.ports.count { reorderPorts(reordered) }

        resolvedInputs = ["inputA", "inputB", "inputC"].map { name in let port: Port? = findPort(named: name); return port as? any GPUStreamPort }
        let output: Port? = findPort(named: "outputStream")
        resolvedOutput = output as? any GPUStreamPort
        resolvedBValue = findPort(named: "inputBValue")
        resolvedCValue = findPort(named: "inputCValue")

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

    private struct StreamMathUniforms
    {
        var count: UInt32
        var operation: UInt32
        var reserved0: UInt32 = 0
        var reserved1: UInt32 = 0
        var b: simd_float4
        var c: simd_float4
    }

    static func kernelSource(for elementType: PortType) -> String
    {
        let type = StreamKernel.metalType(elementType)
        let fields = streamFields.map { StreamKernelField(name: $0, elementType: elementType) }
        let operations = StreamMathOperation.allCases.map { operation in
            let expression: String
            switch operation
            {
            case .add: expression = "a + b"
            case .subtract: expression = "a - b"
            case .multiply: expression = "a * b"
            case .divide: expression = "a / b"
            case .multiplyAdd: expression = "a + b * c"
            case .mix: expression = "mix(a, b, c)"
            case .minimum: expression = "min(a, b)"
            case .maximum: expression = "max(a, b)"
            }
            return "        case \(operation.kernelIndex): value = \(expression); break;"
        }.joined(separator: "\n")

        return StreamOperationKernel.source(
            inputs: fields,
            uniforms: """
            struct StreamOperationUniforms {
                uint count;
                uint operation;
                uint reserved0;
                uint reserved1;
                float4 b;
                float4 c;
            };
            """,
            helpers: "",
            outputType: elementType,
            body: """
                const \(type) a = inputs.a.read(id);
                const \(type) b = fabricOperand(inputs.b, id, \(StreamOperationKernel.constant("uniforms.b", as: elementType)));
                const \(type) c = fabricOperand(inputs.c, id, \(StreamOperationKernel.constant("uniforms.c", as: elementType)));
                switch (uniforms.operation) {
            \(operations)
                    default: value = a; break;
                }
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

        guard let count = resolvedInputs.first??.currentStream?.count else
        {
            output.clearStream()
            return
        }

        var uniforms = StreamMathUniforms(count: UInt32(count.capacity),
                                          operation: operation.kernelIndex,
                                          b: StreamOperationKernel.uniformVector(from: resolvedBValue),
                                          c: StreamOperationKernel.uniformVector(from: resolvedCValue))
        try operationKernel.encode(uniforms: &uniforms, inputs: resolvedInputs, count: count, outputType: elementType, output: output,
                                   label: "Stream Math", commandBuffer: commandBuffer, allocator: context.gpuAllocator)
    }
}
