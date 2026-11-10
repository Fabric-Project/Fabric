//
//  PointsComputeNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI
import simd

// MARK: - Settings

/// The attributes a Points Compute node writes and the function that writes them.
public struct PointsComputeSettings: NodeSettings
{
    public var hasNormals: Bool
    public var hasColors: Bool
    public var hasSizes: Bool
    public var hasTexcoords: Bool
    /// In order: they take the custom slots in this order, and become fields of the output.
    public var customAttributes: [PointsCustomAttribute]
    /// Each is an input port and `inputs.<name>`, read with `read(id)` and `count()`.
    public var streamInputs: [StreamKernelField]
    /// A stream input's name, to write as many points as it has, a GPU-written count included;
    /// empty for the Count input.
    public var countSource: String
    /// Metal source defining `pointsCompute`, which fills one point (see `PointsComputeNode`).
    public var kernelSource: String

    public init(hasNormals: Bool, hasColors: Bool, hasSizes: Bool, hasTexcoords: Bool,
                customAttributes: [PointsCustomAttribute], streamInputs: [StreamKernelField], countSource: String, kernelSource: String)
    {
        self.hasNormals = hasNormals
        self.hasColors = hasColors
        self.hasSizes = hasSizes
        self.hasTexcoords = hasTexcoords
        self.customAttributes = customAttributes
        self.streamInputs = streamInputs
        self.countSource = countSource
        self.kernelSource = kernelSource
    }

    /// Colored, sized points on a breathing sphere.
    public static let standard = PointsComputeSettings(hasNormals: false, hasColors: true, hasSizes: true, hasTexcoords: false,
                                                       customAttributes: [], streamInputs: [], countSource: "",
                                                       kernelSource: PointsComputeNode.defaultKernelSource)

    /// Custom attributes named as shader fields that don't clash with the standard ones, stream
    /// inputs a kernel can declare, and a count source among them.
    func normalized() -> PointsComputeSettings
    {
        var result = self
        result.customAttributes = PointsCustomAttribute.normalized(customAttributes, requiringIdentifiers: true)
            .filter { !Self.standardFieldNames.contains($0.name) }
        result.streamInputs = StreamKernelField.normalized(streamInputs, reserved: [], limit: StreamKernel.maximumInputs)
        if !result.streamInputs.contains(where: { $0.name == countSource }) { result.countSource = "" }
        return result
    }

    static let standardFieldNames: Set<String> = ["position", "normal", "color", "size", "texcoord"]
}

// MARK: - Node

/// Points written every frame on the GPU by a Metal function you write. The node wraps it in a
/// kernel that runs it once per point and stores each attribute its settings turn on.
public final class PointsComputeNode: BaseGPUPointsNode
{
    override public class var name: String { "Points Compute" }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Writes points every frame on the GPU with a Metal function you write: pointsCompute fills one point's position and the attributes the settings turn on, from its index, the streams it reads, the time and Parameters. Bounds are unknown, so the points are never culled." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 100_000, .inputfield, "How many points to write"))),
            ("inputParameters", ParameterPort(parameter: Float4Parameter("Parameters", .zero, .inputfield, "Four values the function reads as uniforms.parameters"))),
            ("outputPoints", NodePort<Satin.Points>(name: "Points", kind: .Outlet, description: "The points the function wrote this frame")),
        ]
    }

    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }
    public var inputParameters: ParameterPort<simd_float4> { port(named: "inputParameters") }

    private(set) var computeSettings: PointsComputeSettings

    /// Binds a missing stream input with no elements.
    private lazy var placeholder: MTLBuffer? = context.device.makeBuffer(length: 16, options: .storageModeShared)

    // Resolved when the settings change, so execution parses, looks up and allocates nothing for them.
    private var pointOutputs: [Output] = []
    private var pointOutputLabels: [String] = []
    private var resolvedInputs: [(any GPUStreamPort)?] = []
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

    public init(context: Context, settings: PointsComputeSettings)
    {
        self.computeSettings = settings.normalized()
        super.init(context: context)
        rebuildStreamPorts()
    }

    public required init(from decoder: any Decoder) throws
    {
        self.computeSettings = ((try? PointsComputeSettings(from: decoder)) ?? .standard).normalized()
        try super.init(from: decoder)
        rebuildStreamPorts()
    }

    /// Stream inputs after Count and Parameters, before the output.
    private func rebuildStreamPorts()
    {
        StreamKernel.syncInputPorts(of: self, fields: computeSettings.streamInputs)
        let order = ["inputCount", "inputParameters"] + computeSettings.streamInputs.map(StreamKernel.inputPortName) + ["outputPoints"]
        let ordered: [Port] = order.compactMap { name in let port: Port? = findPort(named: name); return port }
        if ordered.count == ports.count { reorderPorts(ordered) }

        pointOutputs = Self.outputs(for: computeSettings)
        pointOutputLabels = pointOutputs.map { "Points Compute " + $0.field }
        resolvedInputs = StreamKernel.resolveInputs(of: self, fields: computeSettings.streamInputs)
        countSourceIndex = computeSettings.streamInputs.firstIndex { $0.name == computeSettings.countSource }
    }

    override public var kernelSource: String { Self.generatedSource(for: computeSettings) }
    override public var kernelFunctionName: String { "pointsComputeKernel" }

    override public var settings: (any NodeSettings)? { computeSettings }

    override public func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? PointsComputeSettings else { return }
        computeSettings = settings.normalized()
        rebuildStreamPorts()
        recompileKernel()
        performOnMainAsync { [weak self] in self?._settingsModelStorage?.refreshFromNode() }
        super.apply(settings)
    }

    /// New points every frame.
    override public func inputsChanged() -> Bool { true }

    private struct PointsComputeUniforms
    {
        var count: UInt32
        var time: Float
        var deltaTime: Float
        var reserved: UInt32 = 0
        var parameters: simd_float4
    }

    /// One attribute the kernel writes: what it is, the buffer type, and its layout.
    private struct Output
    {
        let key: PointAttribute
        let field: String
        let fieldType: String
        let bufferType: String
        let defaultValue: String
        let store: String
        let components: Int
        let byteStride: Int

        var layout: AttributeLayout { AttributeLayout(scalar: .float32, components: components, byteOffset: 0, byteStride: byteStride) }
    }

    private static func outputs(for settings: PointsComputeSettings) -> [Output]
    {
        var outputs = [Output(key: .position, field: "position", fieldType: "float3", bufferType: "float4", defaultValue: "float3(0.0)",
                              store: "float4(point.position, 1.0)", components: 3, byteStride: 16)]
        if settings.hasNormals
        {
            outputs.append(Output(key: .normal, field: "normal", fieldType: "float3", bufferType: "float4", defaultValue: "float3(0.0, 0.0, 1.0)",
                                  store: "float4(point.normal, 0.0)", components: 3, byteStride: 16))
        }
        if settings.hasColors
        {
            outputs.append(Output(key: .color, field: "color", fieldType: "float4", bufferType: "float4", defaultValue: "float4(1.0)",
                                  store: "point.color", components: 4, byteStride: 16))
        }
        if settings.hasSizes
        {
            outputs.append(Output(key: .size, field: "size", fieldType: "float", bufferType: "float", defaultValue: "1.0",
                                  store: "point.size", components: 1, byteStride: 4))
        }
        if settings.hasTexcoords
        {
            outputs.append(Output(key: .texcoord, field: "texcoord", fieldType: "float2", bufferType: "float2", defaultValue: "float2(0.0)",
                                  store: "point.texcoord", components: 2, byteStride: 8))
        }
        for custom in settings.customAttributes
        {
            let name = custom.name
            switch custom.components
            {
            case 1:
                outputs.append(Output(key: .custom(name), field: name, fieldType: "float", bufferType: "float", defaultValue: "0.0",
                                      store: "point.\(name)", components: 1, byteStride: 4))
            case 2:
                outputs.append(Output(key: .custom(name), field: name, fieldType: "float2", bufferType: "float2", defaultValue: "float2(0.0)",
                                      store: "point.\(name)", components: 2, byteStride: 8))
            case 3:
                outputs.append(Output(key: .custom(name), field: name, fieldType: "float3", bufferType: "float4", defaultValue: "float3(0.0)",
                                      store: "float4(point.\(name), 0.0)", components: 3, byteStride: 16))
            default:
                outputs.append(Output(key: .custom(name), field: name, fieldType: "float4", bufferType: "float4", defaultValue: "float4(0.0)",
                                      store: "point.\(name)", components: 4, byteStride: 16))
            }
        }
        return outputs
    }

    /// The uniforms and output declarations, the user's source, and a kernel that runs it per point.
    static func generatedSource(for settings: PointsComputeSettings) -> String
    {
        let outputs = outputs(for: settings)
        let fields = outputs.map { "    \($0.fieldType) \($0.field);" }.joined(separator: "\n")
        let buffers = outputs.enumerated().map { "    device \($0.element.bufferType) *\($0.element.field)Buffer [[buffer(\($0.offset + 1))]]," }.joined(separator: "\n")
        let countLimit = settings.countSource.isEmpty ? "uniforms.count" : "inputs.\(settings.countSource).count()"
        let defaults = outputs.map { "    point.\($0.field) = \($0.defaultValue);" }.joined(separator: "\n")
        let stores = outputs.map { "    \($0.field)Buffer[id] = \($0.store);" }.joined(separator: "\n")
        return """
        #include <metal_stdlib>
        using namespace metal;

        \(StreamKernel.preamble)

        \(declarations(fields: fields, streamInputs: settings.streamInputs))

        \(settings.kernelSource)

        kernel void pointsComputeKernel(constant PointsComputeUniforms &uniforms [[buffer(0)]],
        \(buffers)
        \(StreamKernel.inputParameters(settings.streamInputs, firstBuffer: outputs.count + 1))
            uint id [[thread_position_in_grid]]) {
        \(StreamKernel.inputsInitializer(structName: "PointsComputeInputs", fields: settings.streamInputs))
            if (id >= \(countLimit)) { return; }
            PointsComputeOutput point;
        \(defaults)
            pointsCompute(id, uniforms, inputs, point);
        \(stores)
        }
        """
    }

    /// What `pointsCompute` sees, shown in the settings view as well; the stream readers it uses
    /// come before them.
    static func declarations(fields: String, streamInputs: [StreamKernelField]) -> String
    {
        """
        struct PointsComputeUniforms {
            uint count;
            float time;
            float deltaTime;
            uint reserved;
            float4 parameters;
        };

        \(StreamKernel.inputsStruct(named: "PointsComputeInputs", fields: streamInputs))

        struct PointsComputeOutput {
        \(fields)
        };
        """
    }

    static func declarations(for settings: PointsComputeSettings) -> String
    {
        declarations(fields: outputs(for: settings).map { "    \($0.fieldType) \($0.field);" }.joined(separator: "\n"),
                     streamInputs: settings.streamInputs)
    }

    override public func publish(pipeline: MTLComputePipelineState, executionInfo: GraphExecutionInfo,
                                 commandBuffer: MTLCommandBuffer) throws -> Satin.Points?
    {
        guard let placeholder,
              let pointCount = StreamKernel.count(from: resolvedInputs, countSourceIndex: countSourceIndex, fallback: max(inputCount.value ?? 0, 0))
        else { return nil }
        let count = pointCount.capacity

        outputBufferScratch.removeAll(keepingCapacity: true)
        for (output, label) in zip(pointOutputs, pointOutputLabels)
        {
            outputBufferScratch.append(try context.gpuAllocator.makeBuffer(length: count * output.byteStride, memoryClass: .gpuOnly, label: label))
        }

        // Fresh buffers hold nothing until the kernel runs, so with no encoder nothing is published.
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Unable to encode Points Compute")
        }
        var uniforms = PointsComputeUniforms(count: UInt32(count),
                                             time: Float(executionInfo.timing.time),
                                             deltaTime: Float(executionInfo.timing.deltaTime),
                                             parameters: inputParameters.value ?? .zero)
        encoder.label = "Points Compute"
        encoder.setBytes(&uniforms, length: MemoryLayout<PointsComputeUniforms>.stride, index: 0)
        for (index, buffer) in outputBufferScratch.enumerated()
        {
            encoder.setBuffer(buffer, offset: 0, index: index + 1)
        }
        StreamKernel.bind(resolvedInputs, encoder: encoder, firstBuffer: pointOutputs.count + 1, placeholder: placeholder, layouts: &layoutScratch)
        Self.dispatchPerPoint(encoder, pipeline: pipeline, count: count)
        encoder.endEncoding()

        let attributes: [(PointAttribute, PublishedAttribute)] = zip(pointOutputs, outputBufferScratch).map { output, buffer in
            (output.key, PublishedAttribute(adopting: buffer, layout: output.layout, count: count))
        }
        // A counted input's GPU count is a whole set of draw arguments, so the points draw by it.
        switch pointCount
        {
        case .known:
            return try Satin.Points(attributes: attributes, topology: .implicit, bounds: .unknown)
        case let .gpu(arguments, _):
            return try Satin.Points(attributes: attributes, topology: .implicit, bounds: .unknown,
                                    drawArguments: arguments)
        }
    }

    static let defaultKernelSource = """
    // Fill one point. Its index is id, of uniforms.count; uniforms.time and uniforms.deltaTime are in
    // seconds; uniforms.parameters is the Parameters input. Read a stream input with
    // inputs.<name>.read(id). Unset fields keep their defaults.
    void pointsCompute(uint id, constant PointsComputeUniforms &uniforms, thread const PointsComputeInputs &inputs, thread PointsComputeOutput &point)
    {
        const float fraction = (float(id) + 0.5) / float(uniforms.count);
        const float y = 1.0 - 2.0 * fraction;
        const float ring = sqrt(max(0.0, 1.0 - y * y));
        const float angle = float(id) * 2.39996323 + uniforms.time * 0.3;
        const float radius = 1.0 + 0.25 * sin(uniforms.time * 2.0 + y * 6.0);
        point.position = float3(cos(angle) * ring, y, sin(angle) * ring) * radius;
        point.color = float4(0.5 + 0.5 * y, 0.6, 1.0 - 0.5 * y, 1.0);
        point.size = 1.0 + 2.0 * (radius - 0.75);
    }
    """

    // MARK: Settings View

    @MainActor
    @Observable final class SettingsModel
    {
        /// The outputs, inputs and count, applied as they change; the function is the editor's.
        var settings: PointsComputeSettings
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

        private weak var node: PointsComputeNode?

        init(node: PointsComputeNode)
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
        performOnMainSync { AnyView(PointsComputeSettingsView(model: settingsModel)) }
    }

    override public var settingsSize: SettingsViewSize
    {
        .Custom(size: CGSize(width: 980, height: 700))
    }
}

extension PointsComputeNode: MetalKernelSourceEditing
{
    var editableKernelSource: String { computeSettings.kernelSource }

    func applyEditedKernelSource(_ source: String)
    {
        var settings = computeSettings
        settings.kernelSource = source
        setSettings(settings)
    }

    var kernelCompileFailure: String? { kernelFailure }
}

struct PointsComputeSettingsView: View
{
    @Bindable var model: PointsComputeNode.SettingsModel

    var body: some View
    {
        VStack(alignment: .leading, spacing: 12)
        {
            CodeEditorGuidance(
                "Write points on the GPU with a Metal function. `pointsCompute(id, uniforms, inputs, point)` fills point `id` of `uniforms.count`: its position and the attributes turned on below. `uniforms.time`, `uniforms.deltaTime` and `uniforms.parameters` come from the node; read a stream input with `inputs.name.read(id)`, and its length with `inputs.name.count()`.",
                guide: "[Metal Shading Language specification ↗](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)")

            HStack
            {
                Toggle("Normals", isOn: $model.settings.hasNormals)
                Toggle("Colors", isOn: $model.settings.hasColors)
                Toggle("Sizes", isOn: $model.settings.hasSizes)
                Toggle("Texture Coordinates", isOn: $model.settings.hasTexcoords)
            }

            HStack(alignment: .top)
            {
                PointsCustomAttributesEditor(attributes: $model.settings.customAttributes)
                StreamKernelFieldsEditor(title: "Stream Inputs", fields: $model.settings.streamInputs)
            }

            StreamKernelCountSourcePicker(countSource: $model.settings.countSource, inputs: model.settings.normalized().streamInputs)

            MetalKernelDeclarations(declarations: PointsComputeNode.declarations(for: model.settings.normalized()))

            MetalKernelCodeEditor(model: model.editor)
        }
        .padding(10)
    }
}
