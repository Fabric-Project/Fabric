//
//  Connection.swift
//  Fabric
//
//  Created by Anton Marini on 7/29/26.
//

import SwiftUI
import Satin
internal import AnyCodable

public final class Connection: Codable, Identifiable, Hashable
{
    public let id: UUID
    public let outletPortID: UUID
    public let inletPortID: UUID
    public var active: Bool
    {
        didSet
        {
            guard oldValue != active else { return }
            graph?.markExecutionTopologyChanged()
        }
    }

    internal weak var graph: Graph?

    private enum CodingKeys: String, CodingKey
    {
        case id
        case outletPortID
        case inletPortID
        case active
    }

    public init(id: UUID = UUID(), outletPortID: UUID, inletPortID: UUID, active: Bool = true)
    {
        self.id = id
        self.outletPortID = outletPortID
        self.inletPortID = inletPortID
        self.active = active
    }

    public static func == (lhs: Connection, rhs: Connection) -> Bool
    {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }

    public func port(opposite port: Port) -> Port?
    {
        if port.id == outletPortID
        {
            return graph?.nodePort(forID: inletPortID)
        }

        if port.id == inletPortID
        {
            return graph?.nodePort(forID: outletPortID)
        }

        return nil
    }

    public var outletPort: Port?
    {
        graph?.nodePort(forID: outletPortID)
    }

    public var inletPort: Port?
    {
        graph?.nodePort(forID: inletPortID)
    }
}
