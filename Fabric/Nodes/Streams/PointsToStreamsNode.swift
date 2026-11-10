//
//  PointsToStreamsNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI
import simd

/// Splits published Points into streams without copying: each stream is the attribute's own buffer.
/// Points a GPU pass counted give streams that carry that count, so nothing reads past it.
public final class PointsToStreamsNode: Node
{
    override public class var name: String { "Points to Streams" }
    override public class var nodeType: Node.NodeType { .Streams }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Splits points into streams without copying them: positions, and the normals, colors, sizes, texture coordinates, custom attributes and strips its settings add. An attribute the points don't carry outputs nothing." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputPoints", NodePort<Satin.Points>(name: "Points", kind: .Inlet, description: "The points to split")),
            ("outputPositions", NodePort<GPUStream<simd_float3>>(name: "Positions", kind: .Outlet, description: "One position per point")),
        ]
    }

    public var inputPoints: NodePort<Satin.Points> { port(named: "inputPoints") }
    public var outputPositions: NodePort<GPUStream<simd_float3>> { port(named: "outputPositions") }

    private static let normalsPortName = "outputNormals"
    private static let colorsPortName = "outputColors"
    private static let sizesPortName = "outputSizes"
    private static let texcoordsPortName = "outputTexcoords"
    private static let stripStartsPortName = "outputStripStarts"
    private static let stripLengthsPortName = "outputStripLengths"
    private static let stripsClosedPortName = "outputStripsClosed"
    private static let indicesPortName = "outputIndices"
    private static let customPortPrefix = "outputCustom."
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
    /// Set by a settings change, so the next execute splits even an unchanged input.
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

    /// Adds the outputs the settings ask for and removes the rest, keeping each surviving port,
    /// then orders them: Points, Positions, the standard attributes, custom attributes, strips.
    private func rebuildAttributePorts()
    {
        let settings = pointsSettings
        var wanted: [(name: String, displayName: String, portType: PortType, description: String)] = []
        if settings.hasNormals { wanted.append((Self.normalsPortName, "Normals", .Stream(elementType: .Vector3), "One normal per point")) }
        if settings.hasColors { wanted.append((Self.colorsPortName, "Colors", .Stream(elementType: .Vector4), "One color per point")) }
        if settings.hasSizes { wanted.append((Self.sizesPortName, "Sizes", .Stream(elementType: .Float), "One size per point")) }
        if settings.hasTexcoords { wanted.append((Self.texcoordsPortName, "Texture Coordinates", .Stream(elementType: .Vector2), "One texture coordinate per point")) }
        for attribute in settings.customAttributes
        {
            wanted.append((Self.customPortName(attribute), attribute.name, Self.streamType(components: attribute.components),
                           "One \(attribute.name) per point"))
        }
        if settings.hasStrips
        {
            wanted.append((Self.stripStartsPortName, "Strip Starts", .Array(portType: .Int), "Where each strip starts, in order"))
            wanted.append((Self.stripLengthsPortName, "Strip Lengths", .Array(portType: .Int), "How many points each strip takes, in order"))
            wanted.append((Self.stripsClosedPortName, "Strips Closed", .Array(portType: .Bool), "Whether each strip returns to its first point"))
            wanted.append((Self.indicesPortName, "Indices", .Array(portType: .Int), "Indexed points' indices, in the order they connect"))
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
            addDynamicPort(port.portType.makeFreshPort(name: port.displayName, kind: .Outlet, description: port.description), name: port.name)
        }

        let order = ["inputPoints", "outputPositions"] + wanted.map({ $0.name })
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

    // MARK: Execute

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        guard settingsChanged || inputPoints.valueDidChange else { return }
        settingsChanged = false

        let points = inputPoints.value
        // A GPU pass's count travels with every stream, so downstream reads stop where it says.
        let count: GPUStreamCount? = points.map { points in
            if let arguments = points.drawArguments
            {
                return .gpu(arguments, capacity: points.count)
            }
            return .known(points.count)
        }

        var mismatched: [String] = []
        sendStream(points?.position, count: count, as: simd_float3.self, portName: "outputPositions", displayName: "Positions", mismatched: &mismatched)

        let settings = pointsSettings
        if settings.hasNormals
        {
            sendStream(points?.attribute(.normal), count: count, as: simd_float3.self, portName: Self.normalsPortName, displayName: "Normals", mismatched: &mismatched)
        }
        if settings.hasColors
        {
            sendStream(points?.attribute(.color), count: count, as: simd_float4.self, portName: Self.colorsPortName, displayName: "Colors", mismatched: &mismatched)
        }
        if settings.hasSizes
        {
            sendStream(points?.attribute(.size), count: count, as: Float.self, portName: Self.sizesPortName, displayName: "Sizes", mismatched: &mismatched)
        }
        if settings.hasTexcoords
        {
            sendStream(points?.attribute(.texcoord), count: count, as: simd_float2.self, portName: Self.texcoordsPortName, displayName: "Texture Coordinates", mismatched: &mismatched)
        }
        for custom in settings.customAttributes
        {
            let attribute = points?.attribute(.custom(custom.name))
            let portName = Self.customPortName(custom)
            switch custom.components
            {
            case 1: sendStream(attribute, count: count, as: Float.self, portName: portName, displayName: custom.name, mismatched: &mismatched)
            case 2: sendStream(attribute, count: count, as: simd_float2.self, portName: portName, displayName: custom.name, mismatched: &mismatched)
            case 3: sendStream(attribute, count: count, as: simd_float3.self, portName: portName, displayName: custom.name, mismatched: &mismatched)
            default: sendStream(attribute, count: count, as: simd_float4.self, portName: portName, displayName: custom.name, mismatched: &mismatched)
            }
        }
        if settings.hasStrips
        {
            sendStrips(points?.topology)
        }

        setExecutionStatus(mismatched.isEmpty ? nil : .warning("\(mismatched.joined(separator: ", ")) can't be read as the type set here"))
    }

    /// Sends `attribute` as a stream on `portName`, or nothing when the points lack it. An attribute
    /// whose layout isn't the port's element type sends nothing and is named in `mismatched`.
    private func sendStream<Element: GPUStreamElement>(_ attribute: PublishedAttribute?,
                                                      count: GPUStreamCount?,
                                                      as _: Element.Type,
                                                      portName: String,
                                                      displayName: String,
                                                      mismatched: inout [String])
    {
        guard let output = findPort(named: portName) as NodePort<GPUStream<Element>>? else { return }
        guard let attribute, let count else
        {
            output.send(nil)
            return
        }
        do
        {
            output.send(try GPUStream(attribute: attribute, count: count))
        }
        catch
        {
            mismatched.append(displayName)
            output.send(nil)
        }
    }

    /// The points' topology as it is: strips as their starts, lengths and closings, indexed points as
    /// their indices, and points in order as all empty. Streams to Points makes the same topology back.
    private func sendStrips(_ topology: PointTopology?)
    {
        guard let startsPort = findPort(named: Self.stripStartsPortName) as NodePort<ContiguousArray<Int>>?,
              let lengthsPort = findPort(named: Self.stripLengthsPortName) as NodePort<ContiguousArray<Int>>?,
              let closedPort = findPort(named: Self.stripsClosedPortName) as NodePort<ContiguousArray<Bool>>?,
              let indicesPort = findPort(named: Self.indicesPortName) as NodePort<ContiguousArray<Int>>?
        else { return }

        switch topology
        {
        case .none:
            startsPort.send(nil)
            lengthsPort.send(nil)
            closedPort.send(nil)
            indicesPort.send(nil)
        case .strips(let strips)?:
            startsPort.send(ContiguousArray(strips.map { $0.range.lowerBound }))
            lengthsPort.send(ContiguousArray(strips.map { $0.range.count }))
            closedPort.send(ContiguousArray(strips.map(\.closed)))
            indicesPort.send([])
        case .indexed(let indices)?:
            startsPort.send([])
            lengthsPort.send([])
            closedPort.send([])
            indicesPort.send(ContiguousArray(indices.map { Int($0) }))
        case .implicit?:
            startsPort.send([])
            lengthsPort.send([])
            closedPort.send([])
            indicesPort.send([])
        }
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

        private weak var node: PointsToStreamsNode?

        init(node: PointsToStreamsNode)
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
        performOnMainSync { AnyView(PointsToStreamsSettingsView(model: settingsModel)) }
    }

    override public var settingsSize: SettingsViewSize { .Medium }
}

struct PointsToStreamsSettingsView: View
{
    @Bindable var model: PointsToStreamsNode.SettingsModel

    var body: some View
    {
        PointsSettingsForm(settings: $model.settings,
                           caption: "Positions are always an output. Turn on the other per-point streams to split out.")
    }
}
