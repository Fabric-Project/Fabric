//
//  StreamComputeNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI
import simd

// MARK: - Settings

/// The streams a Stream Compute node reads and writes, where its count comes from, and the function.
public struct StreamComputeSettings: NodeSettings
{
    /// Each is an input port and `inputs.<name>`, read with `read(id)` and `count()`.
    public var inputs: [StreamKernelField]
    /// Each is an output port and a field of `out`.
    public var outputs: [StreamKernelField]
    /// An input's name, to write as many elements as it has, a GPU-written count included; empty
    /// for the Count input.
    public var countSource: String
    /// Metal source defining `streamCompute`, which fills one element of every output.
    public var kernelSource: String

    public init(inputs: [StreamKernelField], outputs: [StreamKernelField], countSource: String, kernelSource: String)
    {
        self.inputs = inputs
        self.outputs = outputs
        self.countSource = countSource
        self.kernelSource = kernelSource
    }

    /// A spiral of positions, every frame.
    public static let standard = StreamComputeSettings(inputs: [],
                                                       outputs: [StreamKernelField(name: "position", elementType: .Vector3)],
                                                       countSource: "",
                                                       kernelSource: StreamComputeNode.defaultKernelSource)

    static let maximumOutputs = 8

    /// Inputs and outputs a kernel can declare, and a count source among the inputs.
    func normalized() -> StreamComputeSettings
    {
        var result = self
        result.inputs = StreamKernelField.normalized(inputs, reserved: [], limit: StreamKernel.maximumInputs)
        result.outputs = StreamKernelField.normalized(outputs, reserved: [], limit: Self.maximumOutputs)
        if !result.inputs.contains(where: { $0.name == countSource }) { result.countSource = "" }
        return result
    }
}

// MARK: - Node

/// Streams written on the GPU by a Metal function you write, from the streams it reads. The node
/// wraps it in a kernel that runs it once per element and stores each output.
public final class StreamComputeNode: Node
{
    override public class var name: String { "Stream Compute" }
    override public class var nodeType: Node.NodeType { .Streams }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Writes streams on the GPU with a Metal function you write: streamCompute fills one element of each output from its index, the streams it reads, the time and Parameters. Set the inputs, outputs and count in Settings." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 1_000, .inputfield, "How many elements to write, unless Settings count an input"))),
            ("inputParameters", ParameterPort(parameter: Float4Parameter("Parameters", .zero, .inputfield, "Four values the function reads as uniforms.parameters"))),
            ("inputEveryFrame", ParameterPort(parameter: BoolParameter("Every Frame", true, .button, "Runs every frame, for a function that reads the time; otherwise only when an input changes"))),
        ]
    }

    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }
    public var inputParameters: ParameterPort<simd_float4> { port(named: "inputParameters") }
    public var inputEveryFrame: ParameterPort<Bool> { port(named: "inputEveryFrame") }

    /// Every Frame runs it each frame, though no input changed.
    override public var isDirty: Bool { (inputEveryFrame.value ?? true) || super.isDirty }

    private(set) var computeSettings: StreamComputeSettings
    private let kernel = ComputeKernel()
    /// The kernel or the outputs changed, so the next execution runs whatever the inputs say.
    private var kernelChanged = true
    /// Binds a missing input with no elements.
    private lazy var placeholder: MTLBuffer? = context.device.makeBuffer(length: 16, options: .storageModeShared)

    // Resolved when the settings change, so execution parses, looks up and allocates nothing for them.
    private var resolvedInputs: [(any GPUStreamPort)?] = []
    private var resolvedOutputs: [StreamKernel.ResolvedOutput] = []
    private var countSourceIndex: Int?
    // Scratch kept across executions.
    private var layoutScratch = ContiguousArray<StreamKernel.Layout>()
    private var outputBufferScratch = ContiguousArray<MTLBuffer>()

    public required init(context: Context)
    {
        self.computeSettings = .standard
        super.init(context: context)
        rebuildStreamPorts()
    }

    public init(context: Context, settings: StreamComputeSettings)
    {
        self.computeSettings = settings.normalized()
        super.init(context: context)
        rebuildStreamPorts()
    }

    public required init(from decoder: any Decoder) throws
    {
        self.computeSettings = ((try? StreamComputeSettings(from: decoder)) ?? .standard).normalized()
        try super.init(from: decoder)
        rebuildStreamPorts()
    }

    override public var settings: (any NodeSettings)? { computeSettings }

    override public func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? StreamComputeSettings else { return }
        computeSettings = settings.normalized()
        rebuildStreamPorts()
        if executionState != .disabled { compileKernel() }
        performOnMainAsync { [weak self] in self?._settingsModelStorage?.refreshFromNode() }
        super.apply(settings)
    }

    /// Stream inputs after Count, Parameters and Every Frame; outputs last.
    private func rebuildStreamPorts()
    {
        StreamKernel.syncInputPorts(of: self, fields: computeSettings.inputs)
        StreamKernel.syncOutputPorts(of: self, fields: computeSettings.outputs)
        let order = ["inputCount", "inputParameters", "inputEveryFrame"]
            + computeSettings.inputs.map(StreamKernel.inputPortName)
            + computeSettings.outputs.map(StreamKernel.outputPortName)
        let ordered: [Port] = order.compactMap { name in let port: Port? = findPort(named: name); return port }
        if ordered.count == ports.count { reorderPorts(ordered) }

        resolvedInputs = StreamKernel.resolveInputs(of: self, fields: computeSettings.inputs)
        resolvedOutputs = StreamKernel.resolveOutputs(of: self, fields: computeSettings.outputs, labelPrefix: "Stream Compute")
        countSourceIndex = computeSettings.inputs.firstIndex { $0.name == computeSettings.countSource }
    }

    // MARK: Kernel

    private func compileKernel()
    {
        kernel.compile(source: Self.generatedSource(for: computeSettings), functionNames: ["streamComputeKernel"], device: context.device)
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
        kernel.release()
        try super.disableExecution(renderer: renderer)
    }

    override public func deriveStatuses() -> [NodeStatus] { kernel.failure.map { [NodeStatus.error($0)] } ?? [] }

    private struct StreamComputeUniforms
    {
        var count: UInt32
        var time: Float
        var deltaTime: Float
        var reserved: UInt32 = 0
        var parameters: simd_float4
    }

    /// The declarations, the user's source, and a kernel that runs it per element.
    static func generatedSource(for settings: StreamComputeSettings) -> String
    {
        let outputs = settings.outputs
        let buffers = outputs.enumerated().map { index, field in
            "    device \(StreamKernel.outputStorage(field.elementType).bufferType) *\(field.name)Buffer [[buffer(\(index + 1))]],"
        }.joined(separator: "\n")
        let defaults = outputs.map { "    out.\($0.name) = \(StreamKernel.outputStorage($0.elementType).defaultValue);" }.joined(separator: "\n")
        let stores = outputs.map { "    \($0.name)Buffer[id] = \(StreamKernel.outputStorage($0.elementType).store("out.\($0.name)"));" }.joined(separator: "\n")
        let countLimit = settings.countSource.isEmpty ? "uniforms.count" : "inputs.\(settings.countSource).count()"
        return """
        #include <metal_stdlib>
        using namespace metal;

        \(StreamKernel.preamble)

        \(declarations(for: settings))

        \(settings.kernelSource)

        kernel void streamComputeKernel(constant StreamComputeUniforms &uniforms [[buffer(0)]],
        \(buffers)
        \(StreamKernel.inputParameters(settings.inputs, firstBuffer: outputs.count + 1))
            uint id [[thread_position_in_grid]]) {
        \(StreamKernel.inputsInitializer(structName: "StreamComputeInputs", fields: settings.inputs))
            if (id >= \(countLimit)) { return; }
            StreamComputeOutput out;
        \(defaults)
            streamCompute(id, uniforms, inputs, out);
        \(stores)
        }
        """
    }

    /// What `streamCompute` sees, shown in the settings view as well; the stream readers it uses
    /// come before them.
    static func declarations(for settings: StreamComputeSettings) -> String
    {
        let fields = settings.outputs.map { "    \(StreamKernel.metalType($0.elementType)) \($0.name);" }.joined(separator: "\n")
        return """
        struct StreamComputeUniforms {
            uint count;
            float time;
            float deltaTime;
            uint reserved;
            float4 parameters;
        };

        \(StreamKernel.inputsStruct(named: "StreamComputeInputs", fields: settings.inputs))

        struct StreamComputeOutput {
        \(fields)
        };
        """
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
        guard kernelJustChanged || inputsChanged || (inputEveryFrame.value ?? true) else { return }

        guard let pipeline = kernel.pipelines?.first, let placeholder,
              let count = StreamKernel.count(from: resolvedInputs, countSourceIndex: countSourceIndex, fallback: max(inputCount.value ?? 0, 0))
        else
        {
            for output in resolvedOutputs { output.port?.clearStream() }
            return
        }

        outputBufferScratch.removeAll(keepingCapacity: true)
        for output in resolvedOutputs
        {
            outputBufferScratch.append(try context.gpuAllocator.makeBuffer(length: max(count.capacity, 1) * output.storage.byteStride,
                                                                           memoryClass: .gpuOnly, label: output.label))
        }

        // Fresh buffers hold nothing until the kernel runs, so with no encoder nothing is published.
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Unable to encode Stream Compute")
        }
        var uniforms = StreamComputeUniforms(count: UInt32(count.capacity),
                                             time: Float(executionInfo.timing.time),
                                             deltaTime: Float(executionInfo.timing.deltaTime),
                                             parameters: inputParameters.value ?? .zero)
        encoder.label = "Stream Compute"
        encoder.setBytes(&uniforms, length: MemoryLayout<StreamComputeUniforms>.stride, index: 0)
        for (index, buffer) in outputBufferScratch.enumerated()
        {
            encoder.setBuffer(buffer, offset: 0, index: index + 1)
        }
        StreamKernel.bind(resolvedInputs, encoder: encoder, firstBuffer: resolvedOutputs.count + 1, placeholder: placeholder,
                          layouts: &layoutScratch)
        BaseGPUPointsNode.dispatchPerPoint(encoder, pipeline: pipeline, count: count.capacity)
        encoder.endEncoding()

        for (output, buffer) in zip(resolvedOutputs, outputBufferScratch)
        {
            try output.port?.sendStream(attribute: PublishedAttribute(adopting: buffer, layout: output.layout, count: count.capacity), count: count)
        }
    }

    static let defaultKernelSource = """
    // Fill one element of each output. Its index is id, below uniforms.count (with a counted input,
    // up to its capacity: check inputs.<name>.count()); uniforms.time and uniforms.deltaTime are in
    // seconds; uniforms.parameters is the Parameters input. Read an input with inputs.<name>.read(id).
    // Unset outputs keep their defaults.
    void streamCompute(uint id, constant StreamComputeUniforms &uniforms, thread const StreamComputeInputs &inputs, thread StreamComputeOutput &out)
    {
        const float fraction = (float(id) + 0.5) / float(uniforms.count);
        const float angle = fraction * 24.0 + uniforms.time;
        out.position = float3(cos(angle) * fraction, 2.0 * fraction - 1.0, sin(angle) * fraction);
    }
    """

    // MARK: Settings View

    @MainActor
    @Observable final class SettingsModel
    {
        /// The inputs, outputs and count, applied as they change; the function is the editor's.
        var settings: StreamComputeSettings
        {
            didSet
            {
                guard let node, settings != node.computeSettings else { return }
                var applied = settings
                applied.kernelSource = node.computeSettings.kernelSource
                node.setSettings(applied)
            }
        }
        let editor: MetalKernelEditorModel

        private weak var node: StreamComputeNode?

        init(node: StreamComputeNode)
        {
            self.node = node
            self.settings = node.computeSettings
            self.editor = MetalKernelEditorModel(node: node)
        }

        func refreshFromNode()
        {
            guard let node else { return }
            if settings != node.computeSettings { settings = node.computeSettings }
            editor.refreshFromNode()
        }
    }

    /// Nil until a settings view asks for it.
    private var _settingsModelStorage: SettingsModel?

    var settingsModel: SettingsModel
    {
        performOnMainSync
        {
            if let model = _settingsModelStorage { return model }
            let model = SettingsModel(node: self)
            _settingsModelStorage = model
            return model
        }
    }

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView
    {
        performOnMainSync { AnyView(StreamComputeSettingsView(model: settingsModel)) }
    }

    override public var settingsSize: SettingsViewSize
    {
        .Custom(size: CGSize(width: 980, height: 700))
    }
}

extension StreamComputeNode: MetalKernelSourceEditing
{
    var editableKernelSource: String { computeSettings.kernelSource }

    func applyEditedKernelSource(_ source: String)
    {
        var settings = computeSettings
        settings.kernelSource = source
        setSettings(settings)
    }

    var kernelCompileFailure: String? { kernel.failure }
}

struct StreamComputeSettingsView: View
{
    @Bindable var model: StreamComputeNode.SettingsModel

    var body: some View
    {
        VStack(alignment: .leading, spacing: 12)
        {
            CodeEditorGuidance(
                "Write streams on the GPU with a Metal function. `streamCompute(id, uniforms, inputs, out)` fills element `id` of every output below: `uniforms.count` of them, or the counted input's `inputs.name.count()`. `uniforms.time`, `uniforms.deltaTime` and `uniforms.parameters` come from the node; read an input with `inputs.name.read(id)`.",
                guide: "[Metal Shading Language specification ↗](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)")

            HStack(alignment: .top)
            {
                StreamKernelFieldsEditor(title: "Inputs", fields: $model.settings.inputs)
                StreamKernelFieldsEditor(title: "Outputs", fields: $model.settings.outputs)
            }

            StreamKernelCountSourcePicker(countSource: $model.settings.countSource, inputs: model.settings.normalized().inputs)

            MetalKernelDeclarations(declarations: StreamComputeNode.declarations(for: model.settings.normalized()))

            MetalKernelCodeEditor(model: model.editor)
        }
        .padding(10)
    }
}
