//
//  PointsNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI
import simd

// MARK: - Settings

/// A named per-point attribute of one to four floats, beyond the standard ones.
public struct PointsCustomAttribute: Codable, Equatable, Hashable, Sendable
{
    public var name: String
    /// 1 to 4: a Float, Vector 2, Vector 3 or Vector 4 array input.
    public var components: Int

    public init(name: String, components: Int)
    {
        self.name = name
        self.components = components
    }

    /// `attributes` as Points can take them: named, unique, one to four components, no more than
    /// there are custom slots, and, when `requiringIdentifiers`, named as shader identifiers.
    static func normalized(_ attributes: [PointsCustomAttribute], requiringIdentifiers: Bool) -> [PointsCustomAttribute]
    {
        var seenNames = Set<String>()
        var result: [PointsCustomAttribute] = []
        for attribute in attributes
        {
            let name = attribute.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  !requiringIdentifiers || isIdentifier(name),
                  seenNames.insert(name).inserted,
                  result.count < PointAttribute.customIndices.count
            else { continue }
            result.append(PointsCustomAttribute(name: name, components: min(max(attribute.components, 1), 4)))
        }
        return result
    }

    /// A letter or underscore, then letters, digits or underscores.
    static func isIdentifier(_ name: String) -> Bool
    {
        guard let first = name.unicodeScalars.first, first == "_" || (first.isASCII && first.properties.isAlphabetic) else { return false }
        return name.unicodeScalars.allSatisfy { $0 == "_" || ($0.isASCII && ($0.properties.isAlphabetic || $0.properties.numericType != nil)) }
    }
}

/// Which per-point inputs a Points node has. Positions are always there.
public struct PointsSettings: NodeSettings
{
    public var hasNormals: Bool
    public var hasColors: Bool
    public var hasSizes: Bool
    public var hasTexcoords: Bool
    /// Adds the topology: strip starts, lengths and closings, and indices.
    public var hasStrips: Bool
    /// In order: they take the custom slots in this order.
    public var customAttributes: [PointsCustomAttribute]

    public init(hasNormals: Bool, hasColors: Bool, hasSizes: Bool, hasTexcoords: Bool, hasStrips: Bool,
                customAttributes: [PointsCustomAttribute])
    {
        self.hasNormals = hasNormals
        self.hasColors = hasColors
        self.hasSizes = hasSizes
        self.hasTexcoords = hasTexcoords
        self.hasStrips = hasStrips
        self.customAttributes = customAttributes
    }

    /// Positions only.
    public static let positionsOnly = PointsSettings(hasNormals: false, hasColors: false, hasSizes: false,
                                                     hasTexcoords: false, hasStrips: false, customAttributes: [])

    /// The same settings with custom attributes Points can take (see `PointsCustomAttribute.normalized`).
    func normalized() -> PointsSettings
    {
        var result = self
        result.customAttributes = PointsCustomAttribute.normalized(customAttributes, requiringIdentifiers: false)
        return result
    }
}

// MARK: - Node

/// Builds published Points from streams without copying: each attribute is a stream's own buffer.
public final class PointsNode: Node
{
    override public class var name: String { "Points" }
    override public class var nodeType: Node.NodeType { .Points }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Builds points from streams without copying them: positions, and the normals, colors, sizes, texture coordinates, custom attributes and topology its settings add. Every stream must have the same count; an unwired attribute is left out. Turn arrays into streams with Array to Stream. Draw the points with Points Geometry." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputPositions", NodePort<GPUStream<simd_float3>>(name: "Positions", kind: .Inlet, description: "One position per point")),
            ("outputPoints", NodePort<Satin.Points>(name: "Points", kind: .Outlet, description: "The published points")),
        ]
    }

    public var inputPositions: NodePort<GPUStream<simd_float3>> { port(named: "inputPositions") }
    public var outputPoints: NodePort<Satin.Points> { port(named: "outputPoints") }

    private static let normalsPortName = "inputNormals"
    private static let colorsPortName = "inputColors"
    private static let sizesPortName = "inputSizes"
    private static let texcoordsPortName = "inputTexcoords"
    private static let stripStartsPortName = "inputStripStarts"
    private static let stripLengthsPortName = "inputStripLengths"
    private static let stripsClosedPortName = "inputStripsClosed"
    private static let indicesPortName = "inputIndices"
    private static let customPortPrefix = "inputCustom."
    /// The component count is part of the key, so a key's port type never changes.
    private static func customPortName(_ attribute: PointsCustomAttribute) -> String
    {
        customPortPrefix + attribute.name + "." + String(attribute.components)
    }

    private static func streamType(components: Int) -> PortType
    {
        switch components
        {
        case 1: return .Stream(elementType: .Float)
        case 2: return .Stream(elementType: .Vector2)
        case 3: return .Stream(elementType: .Vector3)
        default: return .Stream(elementType: .Vector4)
        }
    }

    // MARK: Settings

    private(set) var pointsSettings: PointsSettings
    /// Set by a settings change, so the next execute publishes even with unchanged inputs.
    private var settingsChanged = true
    private var executionStatus: NodeStatus?

    public required init(context: Context)
    {
        self.pointsSettings = .positionsOnly
        super.init(context: context)
    }

    public init(context: Context, settings: PointsSettings)
    {
        self.pointsSettings = settings.normalized()
        super.init(context: context)
        rebuildAttributePorts()
    }

    public required init(from decoder: any Decoder) throws
    {
        self.pointsSettings = ((try? PointsSettings(from: decoder)) ?? .positionsOnly).normalized()
        try super.init(from: decoder)
        rebuildAttributePorts()
    }

    override public var settings: (any NodeSettings)? { pointsSettings }

    override public func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? PointsSettings else { return }
        pointsSettings = settings.normalized()
        rebuildAttributePorts()
        settingsChanged = true
        performOnMainAsync { [weak self] in self?._settingsModelStorage?.refreshFromNode() }
        super.apply(settings)
    }

    /// Adds the inputs the settings ask for and removes the rest, keeping each surviving port,
    /// then orders them: Positions, the standard attributes, custom attributes, strips, output.
    private func rebuildAttributePorts()
    {
        let settings = pointsSettings
        var wanted: [(name: String, displayName: String, portType: PortType, description: String)] = []
        if settings.hasNormals { wanted.append((Self.normalsPortName, "Normals", .Stream(elementType: .Vector3), "One normal per point")) }
        if settings.hasColors { wanted.append((Self.colorsPortName, "Colors", .Stream(elementType: .Vector4), "One color per point")) }
        if settings.hasSizes { wanted.append((Self.sizesPortName, "Sizes", .Stream(elementType: .Float), "One size per point, multiplying a material's point size")) }
        if settings.hasTexcoords { wanted.append((Self.texcoordsPortName, "Texture Coordinates", .Stream(elementType: .Vector2), "One texture coordinate per point")) }
        for attribute in settings.customAttributes
        {
            wanted.append((Self.customPortName(attribute), attribute.name, Self.streamType(components: attribute.components),
                           "One \(attribute.name) per point"))
        }
        if settings.hasStrips
        {
            wanted.append((Self.stripStartsPortName, "Strip Starts", .Array(portType: .Int),
                           "Where each strip starts, in order. Empty: each starts where the last ended, the first at 0"))
            wanted.append((Self.stripLengthsPortName, "Strip Lengths", .Array(portType: .Int),
                           "How many points each strip takes, in order. Empty, with no Indices: every point in order, unstripped"))
            wanted.append((Self.stripsClosedPortName, "Strips Closed", .Array(portType: .Bool),
                           "Whether each strip returns to its first point. A strip past the end of this is open"))
            wanted.append((Self.indicesPortName, "Indices", .Array(portType: .Int),
                           "Points in the order they connect, instead of strips when not empty. Not with a GPU count"))
        }

        let wantedNames = Set(wanted.map({ $0.name }))
        let dynamicNames = [Self.normalsPortName, Self.colorsPortName, Self.sizesPortName, Self.texcoordsPortName,
                            Self.stripStartsPortName, Self.stripLengthsPortName, Self.stripsClosedPortName, Self.indicesPortName]
        for port in ports
        {
            guard let registryName = registryKey(of: port),
                  dynamicNames.contains(registryName) || registryName.hasPrefix(Self.customPortPrefix)
            else { continue }
            if !wantedNames.contains(registryName) { removePort(port) }
        }

        for port in wanted where findPort(named: port.name) == nil
        {
            addDynamicPort(port.portType.makeFreshPort(name: port.displayName, kind: .Inlet, description: port.description), name: port.name)
        }

        let order = ["inputPositions"] + wanted.map({ $0.name }) + ["outputPoints"]
        let ordered: [Port] = order.compactMap { name in let port: Port? = findPort(named: name); return port }
        if ordered.count == ports.count { reorderPorts(ordered) }
    }

    // MARK: Status

    override public func deriveStatuses() -> [NodeStatus]
    {
        executionStatus.map { [$0] } ?? []
    }

    private func setExecutionStatus(_ status: NodeStatus?)
    {
        guard status != executionStatus else { return }
        executionStatus = status
        subtitleSubject.send()
    }

    private enum AssemblyProblem: Error
    {
        case partialStream
        case countsDiffer(String)
        case stripsWithGPUCount

        var message: String
        {
            switch self
            {
            case .partialStream: return "Positions covers only part of its buffer; Points can't draw part of a stream yet"
            case .countsDiffer(let name): return "\(name) has a different count from Positions"
            case .stripsWithGPUCount: return "Strips or Indices can't be used with a count the GPU wrote"
            }
        }
    }

    // MARK: Execute

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        guard settingsChanged || ports.contains(where: { $0.kind == .Inlet && $0.valueDidChange }) else { return }
        settingsChanged = false

        guard let positions = inputPositions.value, positions.count.capacity > 0 else
        {
            setExecutionStatus(nil)
            outputPoints.send(nil)
            return
        }

        do
        {
            outputPoints.send(try makePoints(positions: positions))
            setExecutionStatus(nil)
        }
        catch let problem as AssemblyProblem
        {
            setExecutionStatus(.error(problem.message))
            outputPoints.send(nil)
        }
        catch let problem as PointsError
        {
            setExecutionStatus(.error("These streams can't make points: \(problem)"))
            outputPoints.send(nil)
        }
        catch
        {
            throw FabricError(.execution(.failed), severity: .recoverable, message: "Points could not be published: \(error)")
        }
    }

    private func makePoints(positions: GPUStream<simd_float3>) throws -> Satin.Points
    {
        // Points count every element of the position attribute; a shorter view needs a count it lacks.
        let count = positions.count
        if case .known(let known) = count, known != positions.attribute.count { throw AssemblyProblem.partialStream }

        let settings = pointsSettings
        var attributes: [(PointAttribute, PublishedAttribute)] = [(.position, positions.attribute)]
        if settings.hasNormals
        {
            try appendAttribute(.normal, portName: Self.normalsPortName, displayName: "Normals", as: simd_float3.self, count: count, to: &attributes)
        }
        if settings.hasColors
        {
            try appendAttribute(.color, portName: Self.colorsPortName, displayName: "Colors", as: simd_float4.self, count: count, to: &attributes)
        }
        if settings.hasSizes
        {
            try appendAttribute(.size, portName: Self.sizesPortName, displayName: "Sizes", as: Float.self, count: count, to: &attributes)
        }
        if settings.hasTexcoords
        {
            try appendAttribute(.texcoord, portName: Self.texcoordsPortName, displayName: "Texture Coordinates", as: simd_float2.self, count: count, to: &attributes)
        }
        for custom in settings.customAttributes
        {
            let portName = Self.customPortName(custom)
            switch custom.components
            {
            case 1: try appendAttribute(.custom(custom.name), portName: portName, displayName: custom.name, as: Float.self, count: count, to: &attributes)
            case 2: try appendAttribute(.custom(custom.name), portName: portName, displayName: custom.name, as: simd_float2.self, count: count, to: &attributes)
            case 3: try appendAttribute(.custom(custom.name), portName: portName, displayName: custom.name, as: simd_float3.self, count: count, to: &attributes)
            default: try appendAttribute(.custom(custom.name), portName: portName, displayName: custom.name, as: simd_float4.self, count: count, to: &attributes)
            }
        }

        let topology = topology()
        switch count
        {
        case .known:
            return try Satin.Points(attributes: attributes, topology: topology, bounds: .unknown)
        case let .gpu(arguments, _):
            guard case .implicit = topology else { throw AssemblyProblem.stripsWithGPUCount }
            return try Satin.Points(attributes: attributes, topology: .implicit, bounds: .unknown,
                                    drawArguments: arguments)
        }
    }

    /// Adds the stream wired to `portName`, if any. It must carry the same count as Positions: the
    /// same number, or the same GPU count reference.
    private func appendAttribute<Element: GPUStreamElement>(_ key: PointAttribute,
                                                            portName: String,
                                                            displayName: String,
                                                            as _: Element.Type,
                                                            count: GPUStreamCount,
                                                            to attributes: inout [(PointAttribute, PublishedAttribute)]) throws
    {
        guard let stream = (findPort(named: portName) as NodePort<GPUStream<Element>>?)?.value else { return }
        guard stream.count == count else { throw AssemblyProblem.countsDiffer(displayName) }
        attributes.append((key, stream.attribute))
    }

    /// Indices when there are any; else strips from Strip Starts, Strip Lengths and Strips Closed;
    /// else every point in order. Points rejects strips out of order or range, and indices past the end.
    private func topology() -> PointTopology
    {
        guard pointsSettings.hasStrips else { return .implicit }
        let indices = intArray(Self.indicesPortName)
        if !indices.isEmpty
        {
            return .indexed(ContiguousArray(indices.map { UInt32(clamping: $0) }))
        }
        let lengths = intArray(Self.stripLengthsPortName)
        guard !lengths.isEmpty else { return .implicit }
        let starts = intArray(Self.stripStartsPortName)
        let closed = (findPort(named: Self.stripsClosedPortName) as NodePort<ContiguousArray<Bool>>?)?.value ?? []
        var strips = ContiguousArray<PointStrip>()
        var nextStart = 0
        for (index, length) in lengths.enumerated()
        {
            let start = index < starts.count ? max(starts[index], 0) : nextStart
            let end = start + max(length, 0)
            strips.append(PointStrip(range: start ..< end, closed: index < closed.count && closed[index]))
            nextStart = end
        }
        return .strips(strips)
    }

    private func intArray(_ portName: String) -> ContiguousArray<Int>
    {
        (findPort(named: portName) as NodePort<ContiguousArray<Int>>?)?.value ?? []
    }

    // MARK: Settings View

    @MainActor
    @Observable final class SettingsModel
    {
        var settings: PointsSettings
        {
            didSet
            {
                guard let node, settings != node.pointsSettings else { return }
                node.setSettings(settings)
            }
        }

        private weak var node: PointsNode?

        init(node: PointsNode)
        {
            self.node = node
            self.settings = node.pointsSettings
        }

        func refreshFromNode()
        {
            guard let node, settings != node.pointsSettings else { return }
            settings = node.pointsSettings
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
        performOnMainSync { AnyView(PointsSettingsView(model: settingsModel)) }
    }

    override public var settingsSize: SettingsViewSize { .Medium }
}

struct PointsSettingsView: View
{
    @Bindable var model: PointsNode.SettingsModel

    var body: some View
    {
        PointsSettingsForm(settings: $model.settings,
                           caption: "Positions are always an input. Turn on the other per-point streams these points carry.")
    }
}

/// The toggles and custom attributes of a `PointsSettings`, for every node that takes one.
struct PointsSettingsForm: View
{
    @Binding var settings: PointsSettings
    let caption: String

    var body: some View
    {
        VStack(alignment: .leading)
        {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Normals", isOn: $settings.hasNormals)
            Toggle("Colors", isOn: $settings.hasColors)
            Toggle("Sizes", isOn: $settings.hasSizes)
            Toggle("Texture Coordinates", isOn: $settings.hasTexcoords)
            Toggle("Strips", isOn: $settings.hasStrips)

            Divider()

            PointsCustomAttributesEditor(attributes: $settings.customAttributes)
        }
        .padding()
    }
}

/// Lists custom point attributes, removes them, and adds one by name and component count.
struct PointsCustomAttributesEditor: View
{
    @Binding var attributes: [PointsCustomAttribute]
    @State private var newAttributeName = ""
    @State private var newAttributeComponents = 1

    var body: some View
    {
        VStack(alignment: .leading)
        {
            Text("Custom Attributes")
                .font(.headline)
            ForEach(attributes, id: \.name)
            { attribute in
                PointsCustomAttributeRow(attribute: attribute)
                {
                    attributes.removeAll { $0.name == attribute.name }
                }
            }

            HStack
            {
                TextField("Name", text: $newAttributeName)
                Picker("Components", selection: $newAttributeComponents)
                {
                    ForEach(1 ... 4, id: \.self) { components in
                        Text(components, format: .number).tag(components)
                    }
                }
                .labelsHidden()
                Button("Add", systemImage: "plus")
                {
                    attributes.append(PointsCustomAttribute(name: newAttributeName, components: newAttributeComponents))
                    newAttributeName = ""
                }
                .disabled(newAttributeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct PointsCustomAttributeRow: View
{
    let attribute: PointsCustomAttribute
    let remove: () -> Void

    var body: some View
    {
        HStack
        {
            Text(attribute.name)
            Spacer()
            Text("\(attribute.components) components")
                .foregroundStyle(.secondary)
            Button("Remove", systemImage: "minus", action: remove)
                .labelStyle(.iconOnly)
        }
    }
}
