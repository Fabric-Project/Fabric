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
    /// Adds Strip Lengths and Closed inputs, which split the points into separate strips.
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

/// Builds published Points from arrays: positions, and the per-point inputs its settings add.
public final class PointsNode: Node
{
    override public class var name: String { "Points" }
    override public class var nodeType: Node.NodeType { .Points }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Builds points from arrays: positions, and the normals, colors, sizes, texture coordinates, custom attributes and strips its settings add. An array shorter than Positions repeats its last value. Draw them with Points Geometry." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet, description: "One position per point")),
            ("outputPoints", NodePort<Satin.Points>(name: "Points", kind: .Outlet, description: "The published points")),
        ]
    }

    public var inputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "inputPositions") }
    public var outputPoints: NodePort<Satin.Points> { port(named: "outputPoints") }

    private static let normalsPortName = "inputNormals"
    private static let colorsPortName = "inputColors"
    private static let sizesPortName = "inputSizes"
    private static let texcoordsPortName = "inputTexcoords"
    private static let stripLengthsPortName = "inputStripLengths"
    private static let closedPortName = "inputClosed"
    private static let customPortPrefix = "inputCustom."
    /// The component count is part of the key, so a key's port type never changes: a changed
    /// count is a new port, and the node only ever adds and removes ports.
    private static func customPortName(_ attribute: PointsCustomAttribute) -> String
    {
        customPortPrefix + attribute.name + "." + String(attribute.components)
    }

    // MARK: Settings

    private(set) var pointsSettings: PointsSettings
    /// Set by a settings change, so the next execute publishes even with unchanged inputs.
    private var settingsChanged = true

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
        if settings.hasNormals { wanted.append((Self.normalsPortName, "Normals", .Array(portType: .Vector3), "One normal per point")) }
        if settings.hasColors { wanted.append((Self.colorsPortName, "Colors", .Array(portType: .Color), "One color per point")) }
        if settings.hasSizes { wanted.append((Self.sizesPortName, "Sizes", .Array(portType: .Float), "One size per point, multiplying a material's point size")) }
        if settings.hasTexcoords { wanted.append((Self.texcoordsPortName, "Texture Coordinates", .Array(portType: .Vector2), "One texture coordinate per point")) }
        for attribute in settings.customAttributes
        {
            wanted.append((Self.customPortName(attribute), attribute.name, Self.customPortType(components: attribute.components),
                           "One \(attribute.name) per point"))
        }
        if settings.hasStrips
        {
            wanted.append((Self.stripLengthsPortName, "Strip Lengths", .Array(portType: .Int),
                           "How many points each strip takes, in order. Empty draws one strip through every point"))
        }

        let wantedNames = Set(wanted.map({ $0.name }))
        let dynamicNames = [Self.normalsPortName, Self.colorsPortName, Self.sizesPortName, Self.texcoordsPortName, Self.stripLengthsPortName, Self.closedPortName]
        for port in ports
        {
            guard let registryName = registryKey(of: port),
                  dynamicNames.contains(registryName) || registryName.hasPrefix(Self.customPortPrefix)
            else { continue }
            if !wantedNames.contains(registryName), !(registryName == Self.closedPortName && settings.hasStrips)
            {
                removePort(port)
            }
        }

        for port in wanted
        {
            if findPort(named: port.name) == nil
            {
                addDynamicPort(port.portType.makeFreshPort(name: port.displayName, kind: .Inlet, description: port.description), name: port.name)
            }
        }
        if settings.hasStrips, findPort(named: Self.closedPortName) == nil
        {
            addDynamicPort(ParameterPort(parameter: BoolParameter("Closed", false, .button, "When enabled, every strip returns to its first point")),
                           name: Self.closedPortName)
        }

        let order = ["inputPositions"] + wanted.map({ $0.name }) + (settings.hasStrips ? [Self.closedPortName] : []) + ["outputPoints"]
        let ordered: [Port] = order.compactMap { name in let port: Port? = findPort(named: name); return port }
        if ordered.count == ports.count { reorderPorts(ordered) }
    }

    private static func customPortType(components: Int) -> PortType
    {
        switch components
        {
        case 1: return .Array(portType: .Float)
        case 2: return .Array(portType: .Vector2)
        case 3: return .Array(portType: .Vector3)
        default: return .Array(portType: .Vector4)
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

        let positions = inputPositions.value ?? []
        guard !positions.isEmpty else
        {
            outputPoints.send(nil, force: true)
            return
        }

        do
        {
            outputPoints.send(try makePoints(positions: positions), force: true)
        }
        catch
        {
            throw FabricError(.execution(.failed), severity: .recoverable, message: "Points could not be published: \(error)")
        }
    }

    private func makePoints(positions: ContiguousArray<simd_float3>) throws -> Satin.Points
    {
        let allocator = context.gpuAllocator
        let count = positions.count
        let settings = pointsSettings
        var attributes: [(PointAttribute, PublishedAttribute)] = [
            (.position, try PublishedAttribute.publishing(positions, scalar: .float32, components: 3, allocator: allocator, label: "Positions")),
        ]

        if settings.hasNormals
        {
            let normals = Self.padded(arrayValue(Self.normalsPortName, as: simd_float3.self), to: count, filler: [0, 0, 1])
            attributes.append((.normal, try PublishedAttribute.publishing(normals, scalar: .float32, components: 3, allocator: allocator, label: "Normals")))
        }
        if settings.hasColors
        {
            let colors = Self.padded(arrayValue(Self.colorsPortName, as: simd_float4.self), to: count, filler: [1, 1, 1, 1])
            attributes.append((.color, try PublishedAttribute.publishing(colors, scalar: .float32, components: 4, allocator: allocator, label: "Colors")))
        }
        if settings.hasSizes
        {
            let sizes = Self.padded(arrayValue(Self.sizesPortName, as: Float.self), to: count, filler: 1)
            attributes.append((.size, try PublishedAttribute.publishing(sizes, scalar: .float32, components: 1, allocator: allocator, label: "Sizes")))
        }
        if settings.hasTexcoords
        {
            let texcoords = Self.padded(arrayValue(Self.texcoordsPortName, as: simd_float2.self), to: count, filler: .zero)
            attributes.append((.texcoord, try PublishedAttribute.publishing(texcoords, scalar: .float32, components: 2, allocator: allocator, label: "Texture Coordinates")))
        }
        for custom in settings.customAttributes
        {
            let portName = Self.customPortName(custom)
            let attribute: PublishedAttribute
            switch custom.components
            {
            case 1:
                attribute = try PublishedAttribute.publishing(Self.padded(arrayValue(portName, as: Float.self), to: count, filler: 0),
                                                              scalar: .float32, components: 1, allocator: allocator, label: custom.name)
            case 2:
                attribute = try PublishedAttribute.publishing(Self.padded(arrayValue(portName, as: simd_float2.self), to: count, filler: .zero),
                                                              scalar: .float32, components: 2, allocator: allocator, label: custom.name)
            case 3:
                attribute = try PublishedAttribute.publishing(Self.padded(arrayValue(portName, as: simd_float3.self), to: count, filler: .zero),
                                                              scalar: .float32, components: 3, allocator: allocator, label: custom.name)
            default:
                attribute = try PublishedAttribute.publishing(Self.padded(arrayValue(portName, as: simd_float4.self), to: count, filler: .zero),
                                                              scalar: .float32, components: 4, allocator: allocator, label: custom.name)
            }
            attributes.append((.custom(custom.name), attribute))
        }

        return try Satin.Points(attributes: attributes, topology: topology(pointCount: count), bounds: .of(positions))
    }

    /// Strips from Strip Lengths, in order, stopping at the last point; every point when there are none.
    private func topology(pointCount: Int) -> PointTopology
    {
        guard pointsSettings.hasStrips else { return .implicit }
        let lengths = arrayValue(Self.stripLengthsPortName, as: Int.self)
        let closed = (findPort(named: Self.closedPortName) as ParameterPort<Bool>?)?.value ?? false
        guard !lengths.isEmpty else { return .strips([PointStrip(range: 0 ..< pointCount, closed: closed)]) }
        var strips = ContiguousArray<PointStrip>()
        var start = 0
        for length in lengths where start < pointCount
        {
            let end = min(start + max(length, 0), pointCount)
            strips.append(PointStrip(range: start ..< end, closed: closed))
            start = end
        }
        return .strips(strips)
    }

    private func arrayValue<Element: PortValueRepresentable>(_ portName: String, as _: Element.Type) -> ContiguousArray<Element>
    {
        (findPort(named: portName) as NodePort<ContiguousArray<Element>>?)?.value ?? []
    }

    /// `values` cut or extended to `count`: past its end, its last value repeats, or `filler` when empty.
    private static func padded<Value>(_ values: ContiguousArray<Value>, to count: Int, filler: Value) -> ContiguousArray<Value>
    {
        if values.count == count { return values }
        if values.count > count { return ContiguousArray(values.prefix(count)) }
        var result = values
        result.append(contentsOf: repeatElement(values.last ?? filler, count: count - values.count))
        return result
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
        VStack(alignment: .leading)
        {
            Text("Positions are always an input. Turn on the other per-point inputs these points carry.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Normals", isOn: $model.settings.hasNormals)
            Toggle("Colors", isOn: $model.settings.hasColors)
            Toggle("Sizes", isOn: $model.settings.hasSizes)
            Toggle("Texture Coordinates", isOn: $model.settings.hasTexcoords)
            Toggle("Strips", isOn: $model.settings.hasStrips)

            Divider()

            PointsCustomAttributesEditor(attributes: $model.settings.customAttributes)
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
