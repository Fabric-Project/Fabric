//
//  PortKey.swift
//  Fabric
//

import Foundation

/// What a node finds one of its ports by. Node code chooses its own keys; a
/// key is the port's identity across saves, settings changes and device
/// reconnects, so a dynamic port's key is whatever names it stably: a device
/// element, a script parameter, a timeline track.
public indirect enum PortKey: Hashable, CustomStringConvertible
{
    /// A port the node declares for itself.
    case own(String)
    /// A subgraph node's proxy for the port at `inner` on its inner node `node`.
    case proxy(node: UUID, inner: PortKey)

    public var description: String
    {
        switch self
        {
        case .own(let name): return name
        case .proxy(let node, let inner): return "\(node.uuidString)/\(inner)"
        }
    }
}

/// A port in a graph: the node it is on and its key there.
public struct PortAddress: Hashable, CustomStringConvertible
{
    public let node: UUID
    public let key: PortKey

    public init(node: UUID, key: PortKey)
    {
        self.node = node
        self.key = key
    }

    public var description: String { "\(node.uuidString)/\(key)" }
}

/// A port's document-owned state: the value an unwired parameter inlet rests
/// at, under the port's key. Nothing else about a port belongs to the
/// document; its type, order and metadata are the code's, and its wires and
/// publishing are the graph's.
public struct PortState: Equatable, Codable
{
    public let key: PortKey
    public let value: PortValue

    public init(key: PortKey, value: PortValue)
    {
        self.key = key
        self.value = value
    }
}
