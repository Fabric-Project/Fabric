//
//  StreamKernel.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// A named stream a compute kernel reads or writes: an input port and `inputs.<name>`, or an output
/// port and `out.<name>`.
public struct StreamKernelField: Codable, Equatable, Hashable, Sendable
{
    public var name: String
    /// The element type's name, one of `PortType.streamElementTypes`, as settings save it.
    public var elementTypeName: String

    public init(name: String, elementType: PortType)
    {
        self.name = name
        self.elementTypeName = elementType.rawValue
    }

    public var elementType: PortType { PortType(rawValue: elementTypeName) ?? .Float }

    /// `fields` a kernel can declare: named as shader identifiers, unique, not one of `reserved`,
    /// of a stream element type, and no more than `limit`.
    static func normalized(_ fields: [StreamKernelField], reserved: Set<String>, limit: Int) -> [StreamKernelField]
    {
        var seen = reserved
        var result: [StreamKernelField] = []
        for field in fields
        {
            let name = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard PointsCustomAttribute.isIdentifier(name),
                  seen.insert(name).inserted,
                  let elementType = PortType(rawValue: field.elementTypeName),
                  PortType.streamElementTypes.contains(elementType),
                  result.count < limit
            else { continue }
            result.append(StreamKernelField(name: name, elementType: elementType))
        }
        return result
    }
}

/// What stream inputs and outputs mean in a generated kernel: the Metal types that read them, the
/// buffers they bind to, and the ports that carry them. Shared by Stream Compute and Points Compute.
enum StreamKernel
{
    /// Each input binds a data buffer and a count buffer, so this many fit beside a kernel's own buffers.
    static let maximumInputs = 6

    /// The port for input `field`. Its element type is part of the key, so a key's port type never changes.
    static func inputPortName(_ field: StreamKernelField) -> String
    {
        "inputStream." + field.name + "." + field.elementTypeName
    }

    static func outputPortName(_ field: StreamKernelField) -> String
    {
        "outputStream." + field.name + "." + field.elementTypeName
    }

    /// The Metal type `read` returns, or an output field holds.
    static func metalType(_ elementType: PortType) -> String
    {
        switch elementType
        {
        case .Int: return "int"
        case .Vector2: return "float2"
        case .Vector3: return "float3"
        case .Vector4, .Quaternion: return "float4"
        default: return "float"
        }
    }

    /// The reader struct for an input of `elementType`.
    static func readerType(_ elementType: PortType) -> String
    {
        switch elementType
        {
        case .Int: return "FabricIntStream"
        case .Vector2: return "FabricFloat2Stream"
        case .Vector3: return "FabricFloat3Stream"
        case .Vector4, .Quaternion: return "FabricFloat4Stream"
        default: return "FabricFloatStream"
        }
    }

    /// How an output of one element type is stored: the buffer's Metal type, bytes per element,
    /// components, scalar, the field's starting value, and the expression that stores field `name`.
    struct OutputStorage
    {
        let bufferType: String
        let byteStride: Int
        let components: Int
        let scalar: AttributeScalar
        let defaultValue: String

        func store(_ expression: String) -> String
        {
            bufferType == "float4" && components == 3 ? "float4(\(expression), 0.0)" : expression
        }
    }

    static func outputStorage(_ elementType: PortType) -> OutputStorage
    {
        switch elementType
        {
        case .Int: return OutputStorage(bufferType: "int", byteStride: 4, components: 1, scalar: .int32, defaultValue: "0")
        case .Vector2: return OutputStorage(bufferType: "float2", byteStride: 8, components: 2, scalar: .float32, defaultValue: "float2(0.0)")
        case .Vector3: return OutputStorage(bufferType: "float4", byteStride: 16, components: 3, scalar: .float32, defaultValue: "float3(0.0)")
        case .Vector4: return OutputStorage(bufferType: "float4", byteStride: 16, components: 4, scalar: .float32, defaultValue: "float4(0.0)")
        case .Quaternion: return OutputStorage(bufferType: "float4", byteStride: 16, components: 4, scalar: .float32, defaultValue: "float4(0.0, 0.0, 0.0, 1.0)")
        default: return OutputStorage(bufferType: "float", byteStride: 4, components: 1, scalar: .float32, defaultValue: "0.0")
        }
    }

    /// Readers for every element type. `count()` is how many elements are valid, a GPU-written
    /// count included; `read(id)` past it gives zero. Precision only changes how a read decodes.
    static let preamble = """
    struct FabricStreamLayout {
        uint capacity;
        uint stride;
        uint offset;
        uint scalar;
        uint hasGPUCount;
        uint reserved0;
        uint reserved1;
        uint reserved2;
    };

    struct FabricStreamData {
        device const uchar *data;
        device const uint *gpuCount;
        FabricStreamLayout layout;

        uint count() const {
            return layout.hasGPUCount != 0 ? min(gpuCount[0], layout.capacity) : layout.capacity;
        }

        // Scalar 0 is float32, 1 float16, 2 int32.
        float component(uint id, uint index) const {
            device const uchar *element = data + layout.offset + id * layout.stride;
            if (layout.scalar == 1) { return float(((device const half *)element)[index]); }
            if (layout.scalar == 2) { return float(((device const int *)element)[index]); }
            return ((device const float *)element)[index];
        }

        int integer(uint id) const {
            return ((device const int *)(data + layout.offset + id * layout.stride))[0];
        }
    };

    struct FabricFloatStream {
        FabricStreamData stream;
        uint count() const { return stream.count(); }
        float read(uint id) const { return id < stream.count() ? stream.component(id, 0) : 0.0; }
    };

    struct FabricIntStream {
        FabricStreamData stream;
        uint count() const { return stream.count(); }
        int read(uint id) const { return id < stream.count() ? stream.integer(id) : 0; }
    };

    struct FabricFloat2Stream {
        FabricStreamData stream;
        uint count() const { return stream.count(); }
        float2 read(uint id) const {
            if (id >= stream.count()) { return float2(0.0); }
            return float2(stream.component(id, 0), stream.component(id, 1));
        }
    };

    struct FabricFloat3Stream {
        FabricStreamData stream;
        uint count() const { return stream.count(); }
        float3 read(uint id) const {
            if (id >= stream.count()) { return float3(0.0); }
            return float3(stream.component(id, 0), stream.component(id, 1), stream.component(id, 2));
        }
    };

    struct FabricFloat4Stream {
        FabricStreamData stream;
        uint count() const { return stream.count(); }
        float4 read(uint id) const {
            if (id >= stream.count()) { return float4(0.0); }
            return float4(stream.component(id, 0), stream.component(id, 1), stream.component(id, 2), stream.component(id, 3));
        }
    };
    """

    /// `struct <name> { <reader> <field>; … };`, what the user's function receives as `inputs`.
    static func inputsStruct(named name: String, fields: [StreamKernelField]) -> String
    {
        let members = fields.map { "    \(readerType($0.elementType)) \($0.name);" }.joined(separator: "\n")
        return "struct \(name) {\n\(members)\n};"
    }

    /// The kernel parameters for `fields`: a data and a count buffer each from `firstBuffer`, then
    /// their layouts. Each line ends with a comma.
    static func inputParameters(_ fields: [StreamKernelField], firstBuffer: Int) -> String
    {
        guard !fields.isEmpty else { return "" }
        var lines: [String] = []
        for (index, field) in fields.enumerated()
        {
            lines.append("    device const uchar *\(field.name)StreamData [[buffer(\(firstBuffer + 2 * index))]],")
            lines.append("    device const uint *\(field.name)StreamCount [[buffer(\(firstBuffer + 2 * index + 1))]],")
        }
        lines.append("    constant FabricStreamLayout *streamLayouts [[buffer(\(firstBuffer + 2 * fields.count))]],")
        return lines.joined(separator: "\n")
    }

    /// Statements that fill `inputs`, a `<structName>`, from the kernel's parameters.
    static func inputsInitializer(structName: String, fields: [StreamKernelField]) -> String
    {
        var lines = ["    \(structName) inputs;"]
        for (index, field) in fields.enumerated()
        {
            lines.append("    inputs.\(field.name).stream.data = \(field.name)StreamData;")
            lines.append("    inputs.\(field.name).stream.gpuCount = \(field.name)StreamCount;")
            lines.append("    inputs.\(field.name).stream.layout = streamLayouts[\(index)];")
        }
        return lines.joined(separator: "\n")
    }

    /// One input's layout as the kernel reads it (`FabricStreamLayout`).
    struct Layout
    {
        var capacity: UInt32
        var stride: UInt32
        var offset: UInt32
        var scalar: UInt32
        var hasGPUCount: UInt32
        var reserved0: UInt32 = 0
        var reserved1: UInt32 = 0
        var reserved2: UInt32 = 0
    }

    /// One output, resolved when the settings change: its port, how it is stored, and its label.
    struct ResolvedOutput
    {
        let port: (any GPUStreamPort)?
        let storage: OutputStorage
        let layout: AttributeLayout
        let label: String
    }

    /// The ports for `fields`, in order: resolved when the settings change, read every execution.
    static func resolveInputs(of node: Node, fields: [StreamKernelField]) -> [(any GPUStreamPort)?]
    {
        fields.map { field in
            let port: Port? = node.findPort(named: inputPortName(field))
            return port as? any GPUStreamPort
        }
    }

    static func resolveOutputs(of node: Node, fields: [StreamKernelField], labelPrefix: String) -> [ResolvedOutput]
    {
        fields.map { field in
            let port: Port? = node.findPort(named: outputPortName(field))
            let storage = outputStorage(field.elementType)
            return ResolvedOutput(port: port as? any GPUStreamPort,
                                  storage: storage,
                                  layout: AttributeLayout(scalar: storage.scalar, components: storage.components, byteOffset: 0, byteStride: storage.byteStride),
                                  label: labelPrefix + " " + field.name)
        }
    }

    /// Binds the streams on `inputs`, in order, from `firstBuffer`; an input with no stream binds
    /// `placeholder` with no elements, so reading it gives zero. `layouts` is scratch storage the
    /// caller keeps, so binding allocates nothing once it has grown.
    static func bind(_ inputs: [(any GPUStreamPort)?], encoder: MTLComputeCommandEncoder, firstBuffer: Int, placeholder: MTLBuffer,
                     layouts: inout ContiguousArray<Layout>)
    {
        guard !inputs.isEmpty else { return }
        layouts.removeAll(keepingCapacity: true)
        for (index, input) in inputs.enumerated()
        {
            guard let stream = input?.currentStream else
            {
                encoder.setBuffer(placeholder, offset: 0, index: firstBuffer + 2 * index)
                encoder.setBuffer(placeholder, offset: 0, index: firstBuffer + 2 * index + 1)
                layouts.append(Layout(capacity: 0, stride: 0, offset: 0, scalar: 0, hasGPUCount: 0))
                continue
            }
            let layout = stream.attribute.layout
            let scalar: UInt32 = layout.scalar == .float16 ? 1 : layout.scalar == .int32 ? 2 : 0
            encoder.setBuffer(stream.attribute.buffer, offset: 0, index: firstBuffer + 2 * index)
            switch stream.count
            {
            case .known(let count):
                encoder.setBuffer(placeholder, offset: 0, index: firstBuffer + 2 * index + 1)
                layouts.append(Layout(capacity: UInt32(count), stride: UInt32(layout.byteStride), offset: UInt32(layout.byteOffset),
                                      scalar: scalar, hasGPUCount: 0))
            case let .gpu(arguments, capacity):
                encoder.setBuffer(arguments.buffer, offset: arguments.offset, index: firstBuffer + 2 * index + 1)
                layouts.append(Layout(capacity: UInt32(capacity), stride: UInt32(layout.byteStride), offset: UInt32(layout.byteOffset),
                                      scalar: scalar, hasGPUCount: 1))
            }
        }
        layouts.withUnsafeBytes { bytes in
            if let address = bytes.baseAddress
            {
                encoder.setBytes(address, length: bytes.count, index: firstBuffer + 2 * inputs.count)
            }
        }
    }

    /// The count source's count, or `fallback` known elements: nil when there is nothing to write.
    static func count(from inputs: [(any GPUStreamPort)?], countSourceIndex: Int?, fallback: Int) -> GPUStreamCount?
    {
        if let countSourceIndex
        {
            guard let stream = inputs[countSourceIndex]?.currentStream, stream.count.capacity > 0 else { return nil }
            return stream.count
        }
        return fallback > 0 ? .known(fallback) : nil
    }

    /// Adds an input port for each of `fields` and removes stream inputs no field names, keeping
    /// each surviving port.
    static func syncInputPorts(of node: Node, fields: [StreamKernelField])
    {
        syncPorts(of: node, prefix: "inputStream.", wanted: fields.map { (inputPortName($0), $0, PortKind.Inlet) })
    }

    static func syncOutputPorts(of node: Node, fields: [StreamKernelField])
    {
        syncPorts(of: node, prefix: "outputStream.", wanted: fields.map { (outputPortName($0), $0, PortKind.Outlet) })
    }

    private static func syncPorts(of node: Node, prefix: String, wanted: [(name: String, field: StreamKernelField, kind: PortKind)])
    {
        let wantedNames = Set(wanted.map(\.name))
        for port in node.ports
        {
            guard let registryName = node.registryKey(of: port), registryName.hasPrefix(prefix), !wantedNames.contains(registryName) else { continue }
            node.removePort(port)
        }
        for port in wanted where (node.findPort(named: port.name) as Port?) == nil
        {
            let type = PortType.Stream(elementType: port.field.elementType)
            node.addDynamicPort(type.makeFreshPort(name: port.field.name, kind: port.kind, description: "The \(port.field.name) stream"), name: port.name)
        }
    }
}
