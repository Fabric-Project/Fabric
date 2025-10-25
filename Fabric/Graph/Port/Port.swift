//
//  Port.swift
//  Fabric
//
//  Created by Anton Marini on 10/19/25.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

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

extension UTType
{
    static var outletData: UTType { UTType(exportedAs: "info.vade.v.outletData") }
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
    
    public var published: Bool = false
    
    // Kind of lame, but necessary to avoid some type based bullshit.
    public private(set) var parameter:(any Parameter)? = nil
        
    // Maybe a bit too verbose?
//    public var value: (any FabricPort)? { fatalError("override") }
    @ObservationIgnored public var portType: PortType { fatalError("Must be implemented") }
    @ObservationIgnored public var valueDidChange:Bool = true

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
    
    public init(name: String, kind: PortKind, id:UUID)
    {
        self.id = id
        self.kind = kind
        self.name = name
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
    }
    
    required public  init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decode(PortKind.self, forKey: .kind)
        self.published = try container.decodeIfPresent(Bool.self, forKey: .published) ?? false
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

        let connectedPortIds = self.connections.map( { $0.id } )
        
        try container.encode(connectedPortIds, forKey: .connections)
    }
    
    public func connect(to other: Port) { fatalError("override") }
    public func disconnect(from other: Port) { fatalError("override") }
    public func disconnectAll() { fatalError("override") }

}
    
