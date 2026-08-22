//
//  Port.swift
//  Fabric
//
//  Created by Anton Marini on 10/19/25.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Satin

public enum PortKind : String, Codable
{
    case Inlet
    case Outlet
}


// TODO: This should maybe be removed?
public enum PortDirection : String, Codable
{
    case Vertical
    case Horizontal
}


struct OutletData : Codable
{
    let portID: UUID
    init(portID: UUID)
    {
        self.portID = portID
    }
}

extension OutletData :Transferable
{
    static var transferRepresentation: some TransferRepresentation
    {
        CodableRepresentation(contentType: .outletData)
    }
}

struct InletData : Codable
{
    let portID: UUID
    init(portID: UUID)
    {
        self.portID = portID
    }
}

extension InletData :Transferable
{
    static var transferRepresentation: some TransferRepresentation
    {
        CodableRepresentation(contentType: .inletData)
    }
}

extension UTType
{
    static var outletData: UTType { UTType(exportedAs: "info.vade.v.outlet-data") }
    static var inletData: UTType { UTType(exportedAs: "info.vade.v.inlet-data") }
}


// Non Generic Base Port Class, dont use directly
@Observable public class Port : Identifiable, Hashable, Equatable, Codable, CustomDebugStringConvertible
{
    public static func == (lhs: Port, rhs: Port) -> Bool
    {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
        hasher.combine(published)
        hasher.combine(name)
    }
    
    /// Mutable only via hydrate(from:) during decode, which adopts the
    /// document's saved identity so UUID-keyed connections can rebind.
    public private(set) var id:UUID

    public let name: String

    public var portDescription: String = ""

    public var published: Bool = false

    public var publishedName: String? = nil

    // Kind of lame, but necessary to avoid some type based bullshit.
    // TODO: Figure out a way to hide setting this (seems not good)
    // unless its a ParameterPort? 
    @ObservationIgnored public var parameter:(any Parameter)? = nil
        
    // Maybe a bit too verbose?
    @ObservationIgnored public var portType: PortType { fatalError("Must be implemented") }
    
    @ObservationIgnored public var valueDidChange:Bool = true

    /// Runtime-polymorphic read for ports whose concrete type is only known at
    /// runtime — routing nodes' boxed forwarding, Iterator's count resolution,
    /// and layout copying. Pairs with sendBoxed.
    internal func snapshotValue() -> PortValue? { nil }
    internal func restoreValue(from boxed: PortValue?) { }

    /// Unboxes `boxed` into the port's native type and propagates to connected inlets via `send`.
    /// Use this to deliver a PortValue through a port whose concrete type is only known at runtime.
    internal func sendBoxed(_ boxed: PortValue?) { }

    /// Forced variant for stateful nodes that need to publish a new event even when the boxed value
    /// compares equal to the previous value.
    internal func sendBoxed(_ boxed: PortValue?, force: Bool) { sendBoxed(boxed) }
    
    @ObservationIgnored public weak var node: Node?
    @ObservationIgnored internal var onValueChanged: (() -> Void)?

    public internal(set) var connections: [Connection] = []
    @ObservationIgnored public let kind: PortKind
    @ObservationIgnored public let direction:PortDirection = .Horizontal
    @ObservationIgnored public var color:Color
    @ObservationIgnored public var backgroundColor:Color

    public var debugDescription: String
    {
        return "\(self.node?.debugDescription ?? "No Node!!") - \(String(describing: type(of: self)))  \(id)"
    }
    
    public init(name: String, kind: PortKind, description: String = "", id:UUID)
    {
        self.id = id
        self.kind = kind
        self.name = name
        self.portDescription = description
        self.color = .clear
        self.backgroundColor = .clear
    }
    
    enum CodingKeys : String, CodingKey
    {
        case id
        case name
        case connections
        case kind
        case direction
        case published
        case publishedName
        case portDescription
    }

    required public  init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decode(PortKind.self, forKey: .kind)
        self.published = try container.decodeIfPresent(Bool.self, forKey: .published) ?? false
        self.publishedName = try container.decodeIfPresent(String.self, forKey: .publishedName)
        self.portDescription = try container.decodeIfPresent(String.self, forKey: .portDescription) ?? ""
        self.color = .clear
        self.backgroundColor = .clear
    }

    public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(published, forKey: .published)

        if let publishedName
        {
            try container.encode(publishedName, forKey: .publishedName)
        }

        if !portDescription.isEmpty
        {
            try container.encode(portDescription, forKey: .portDescription)
        }

        let connectedPortIds = self.connectedPorts.map( { $0.id } )

        try container.encode(connectedPortIds, forKey: .connections)
    }
    
    deinit
    {
        self.connections.removeAll()
//        print("Deinit Port \(self.id)")
    }
    
    /// The display name: publishedName if set, otherwise the port's own name.
    public var displayName: String { publishedName ?? name }

    public var connectedPorts: [Port]
    {
        connections.compactMap { $0.port(opposite: self) }
    }

    public var connectedInlets: [Port]
    {
        connections.compactMap { connection in
            guard connection.outletPortID == id else { return nil }
            return connection.inletPort
        }
    }

    public var connectedOutlets: [Port]
    {
        connections.compactMap { connection in
            guard connection.inletPortID == id else { return nil }
            return connection.outletPort
        }
    }

    internal var connectedOutletsForActiveConnections: [Port]
    {
        connections.compactMap { connection in
            guard connection.active,
                  connection.inletPortID == id
            else { return nil }

            return connection.outletPort
        }
    }

    public func connection(to port: Port) -> Connection?
    {
        connections.first { connection in
            connection.port(opposite: self)?.id == port.id
        }
    }

    public func setConnectionsActive(_ active: Bool)
    {
        for connection in connections
        {
            connection.active = active
        }
    }

    /// Hover-tooltip string for this port: `displayName: type` plus the
    /// current value when available.
    public var inspectionTooltip: String {
        let head = "\(displayName): \(portType.rawValue)"
        guard let value = snapshotValue() else { return head }

        return "\(head) - \(portType.previewString(for: value))"
    }

    /// Applies document-owned state from a decoded snapshot onto this
    /// code-declared port: identity (connections are keyed by port UUID),
    /// published state, and — when the types still agree — the persisted value.
    /// Code-owned metadata (name, description, parameter range and control
    /// type) deliberately stays as declared; the document does not own it.
    /// Must run before the port is registered — the registry indexes by id.
    internal func hydrate(from decoded: Port)
    {
        self.id = decoded.id
        self.published = decoded.published
        self.publishedName = decoded.publishedName

        if decoded.portType == self.portType,
           let boxedValue = decoded.snapshotValue()
        {
            self.restoreValue(from: boxedValue)
        }
    }

    public func canConnect(to other:Port) -> Bool
    {
        if self.kind == .Inlet, self.portType == .Virtual { return true }
        if other.kind == .Inlet, other.portType == .Virtual { return true }
        return self.portType.canConnect(to: other.portType)
    }
    
    public func connect(to other: Port) { fatalError("override") }
    public func disconnect(from other: Port) { fatalError("override") }
    public func disconnectAll() { fatalError("override") }
    public func teardown() { }

}
    
