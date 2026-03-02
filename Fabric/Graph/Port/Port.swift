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


public struct PortAnchorKey: PreferenceKey
{
    public typealias Value = [UUID : Anchor<CGPoint>]
    
    public static var defaultValue: [UUID : Anchor<CGPoint>] = [:]
    
    public static func reduce(value: inout [UUID : Anchor<CGPoint>],
                       nextValue: () -> [UUID : Anchor<CGPoint>])
    {
        // later writers win
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
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
    
    public let id:UUID

    public let name: String

    public var portDescription: String = ""

    public var published: Bool = false
    
    // Kind of lame, but necessary to avoid some type based bullshit.
    // TODO: Figure out a way to hide setting this (seems not good)
    // unless its a ParameterPort? 
    @ObservationIgnored public var parameter:(any Parameter)? = nil
        
    // Maybe a bit too verbose?
    @ObservationIgnored public var portType: PortType { fatalError("Must be implemented") }
    
    @ObservationIgnored public var valueDidChange:Bool = true

    // BARF?
    internal func boxedValue() -> PortValue? { nil }
    internal func setBoxedValue(_ boxed: PortValue?) { }
    
    @ObservationIgnored public weak var node: Node?
    public var connections: [Port] = []
    @ObservationIgnored public let kind: PortKind
    @ObservationIgnored public let direction:PortDirection = .Horizontal
    @ObservationIgnored public var color:Color
    @ObservationIgnored public var backgroundColor:Color

    public var debugDescription: String
    {
        return "\(self.node?.name ?? "No Node!!") - \(String(describing: type(of: self)))  \(id)"
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
        case portDescription
    }

    required public  init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decode(PortKind.self, forKey: .kind)
        self.published = try container.decodeIfPresent(Bool.self, forKey: .published) ?? false
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

        // Only encode if non-empty to save space
        if !portDescription.isEmpty
        {
            try container.encode(portDescription, forKey: .portDescription)
        }

        let connectedPortIds = self.connections.map( { $0.id } )

        try container.encode(connectedPortIds, forKey: .connections)
    }
    
    deinit
    {
        self.connections.removeAll()
//        print("Deinit Port \(self.id)")
    }
    
    public func canConnect(to other:Port) -> Bool
    {
        self.portType.canConnect(to: other.portType)
    }
    
    public func connect(to other: Port) { fatalError("override") }
    public func disconnect(from other: Port) { fatalError("override") }
    public func disconnectAll() { fatalError("override") }
    public func teardown() { }

}
    
