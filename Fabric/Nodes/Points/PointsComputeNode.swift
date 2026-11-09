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
    /// Metal source defining `pointsCompute`, which fills one point (see `PointsComputeNode`).
    public var kernelSource: String

    public init(hasNormals: Bool, hasColors: Bool, hasSizes: Bool, hasTexcoords: Bool,
                customAttributes: [PointsCustomAttribute], kernelSource: String)
    {
        self.hasNormals = hasNormals
        self.hasColors = hasColors
        self.hasSizes = hasSizes
        self.hasTexcoords = hasTexcoords
        self.customAttributes = customAttributes
        self.kernelSource = kernelSource
    }

    /// Colored, sized points on a breathing sphere.
    public static let standard = PointsComputeSettings(hasNormals: false, hasColors: true, hasSizes: true, hasTexcoords: false,
                                                       customAttributes: [], kernelSource: PointsComputeNode.defaultKernelSource)

    /// Custom attributes named as shader fields that don't clash with the standard ones.
    func normalized() -> PointsComputeSettings
    {
        var result = self
        result.customAttributes = PointsCustomAttribute.normalized(customAttributes, requiringIdentifiers: true)
            .filter { !Self.standardFieldNames.contains($0.name) }
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
    override public class var nodeDescription: String { "Writes points every frame on the GPU with a Metal function you write: pointsCompute fills one point's position and the attributes the settings turn on, from its index, the time and Parameters. Bounds are unknown, so the points are never culled." }

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

    public required init(context: Context)
    {
        self.computeSettings = .standard
        super.init(context: context)
    }

    public init(context: Context, settings: PointsComputeSettings)
    {
        self.computeSettings = settings.normalized()
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        self.computeSettings = ((try? PointsComputeSettings(from: decoder)) ?? .standard).normalized()
        try super.init(from: decoder)
    }

    override public var kernelSource: String { Self.generatedSource(for: computeSettings) }
    override public var kernelFunctionName: String { "pointsComputeKernel" }

    override public var settings: (any NodeSettings)? { computeSettings }

    override public func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? PointsComputeSettings else { return }
        computeSettings = settings.normalized()
        invalidateKernel()
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
        let defaults = outputs.map { "    point.\($0.field) = \($0.defaultValue);" }.joined(separator: "\n")
        let stores = outputs.map { "    \($0.field)Buffer[id] = \($0.store);" }.joined(separator: "\n")
        return """
        #include <metal_stdlib>
        using namespace metal;

        \(declarations(fields: fields))

        \(settings.kernelSource)

        kernel void pointsComputeKernel(constant PointsComputeUniforms &uniforms [[buffer(0)]],
        \(buffers)
            uint id [[thread_position_in_grid]]) {
            if (id >= uniforms.count) { return; }
            PointsComputeOutput point;
        \(defaults)
            pointsCompute(id, uniforms, point);
        \(stores)
        }
        """
    }

    /// What `pointsCompute` sees, shown in the settings view as well.
    static func declarations(fields: String) -> String
    {
        """
        struct PointsComputeUniforms {
            uint count;
            float time;
            float deltaTime;
            uint reserved;
            float4 parameters;
        };

        struct PointsComputeOutput {
        \(fields)
        };
        """
    }

    static func declarations(for settings: PointsComputeSettings) -> String
    {
        declarations(fields: outputs(for: settings).map { "    \($0.fieldType) \($0.field);" }.joined(separator: "\n"))
    }

    override public func publish(pipeline: MTLComputePipelineState, executionInfo: GraphExecutionInfo,
                                 commandBuffer: MTLCommandBuffer) throws -> Satin.Points?
    {
        let count = max(inputCount.value ?? 0, 0)
        guard count > 0 else { return nil }

        let outputs = Self.outputs(for: computeSettings)
        let buffers = try outputs.map { output in
            try context.gpuAllocator.makeBuffer(length: count * output.byteStride, memoryClass: .gpuOnly, label: "Points Compute \(output.field)")
        }

        if let encoder = commandBuffer.makeComputeCommandEncoder()
        {
            var uniforms = PointsComputeUniforms(count: UInt32(count),
                                                 time: Float(executionInfo.timing.time),
                                                 deltaTime: Float(executionInfo.timing.deltaTime),
                                                 parameters: inputParameters.value ?? .zero)
            encoder.label = "Points Compute"
            encoder.setBytes(&uniforms, length: MemoryLayout<PointsComputeUniforms>.stride, index: 0)
            for (index, buffer) in buffers.enumerated()
            {
                encoder.setBuffer(buffer, offset: 0, index: index + 1)
            }
            Self.dispatchPerPoint(encoder, pipeline: pipeline, count: count)
            encoder.endEncoding()
        }

        let attributes: [(PointAttribute, PublishedAttribute)] = zip(outputs, buffers).map { output, buffer in
            (output.key, PublishedAttribute(adopting: buffer,
                                            layout: AttributeLayout(scalar: .float32, components: output.components,
                                                                    byteOffset: 0, byteStride: output.byteStride),
                                            count: count))
        }
        return try Satin.Points(attributes: attributes, topology: .implicit, bounds: .unknown)
    }

    static let defaultKernelSource = """
    // Fill one point. Its index is id, of uniforms.count; uniforms.time and uniforms.deltaTime are in
    // seconds; uniforms.parameters is the Parameters input. Unset fields keep their defaults.
    void pointsCompute(uint id, constant PointsComputeUniforms &uniforms, thread PointsComputeOutput &point)
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
        /// Edits wait here until applied, so typing doesn't recompile on every keystroke.
        var draft: PointsComputeSettings

        private weak var node: PointsComputeNode?

        init(node: PointsComputeNode)
        {
            self.node = node
            self.draft = node.computeSettings
        }

        var hasChanges: Bool { node.map { draft != $0.computeSettings } ?? false }

        func applyDraft()
        {
            node?.setSettings(draft)
        }

        func refreshFromNode()
        {
            guard let node else { return }
            draft = node.computeSettings
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

    override public var settingsSize: SettingsViewSize { .Large }
}

struct PointsComputeSettingsView: View
{
    @Bindable var model: PointsComputeNode.SettingsModel

    var body: some View
    {
        VStack(alignment: .leading)
        {
            HStack
            {
                Toggle("Normals", isOn: $model.draft.hasNormals)
                Toggle("Colors", isOn: $model.draft.hasColors)
                Toggle("Sizes", isOn: $model.draft.hasSizes)
                Toggle("Texture Coordinates", isOn: $model.draft.hasTexcoords)
            }

            PointsCustomAttributesEditor(attributes: $model.draft.customAttributes)

            Text(PointsComputeNode.declarations(for: model.draft.normalized()))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            TextEditor(text: $model.draft.kernelSource)
                .font(.body.monospaced())

            HStack
            {
                Text("A function that doesn't compile shows as the node's status.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Apply", action: model.applyDraft)
                    .disabled(!model.hasChanges)
            }
        }
        .padding()
    }
}
