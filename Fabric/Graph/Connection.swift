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
    public internal(set) var active: Bool
    {
        didSet
        {
            guard oldValue != active else { return }
            graph?.markExecutionTopologyChanged()
        }
    }

    /// Unowned so a graph needs no side table; the graph clears it on disconnect and as it
    /// deinitializes.
    internal unowned var graph: Graph?
    {
        didSet { self.graphIdentifier = self.graph.map(ObjectIdentifier.init) }
    }

    /// The graph's identity, compared without loading the graph.
    internal private(set) var graphIdentifier: ObjectIdentifier?
    // Unowned, not weak, so ports avoid Swift side tables. Graph clears these on
    // detach and a port clears its own on deinit.
    internal unowned var outletPortReference: Port?
    internal unowned var inletPortReference: Port?

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
            return inletPortReference
        }

        if port.id == inletPortID
        {
            return outletPortReference
        }

        return nil
    }

    public var outletPort: Port?
    {
        outletPortReference
    }

    public var inletPort: Port?
    {
        inletPortReference
    }
}
