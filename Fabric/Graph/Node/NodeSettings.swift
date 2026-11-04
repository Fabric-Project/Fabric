//
//  NodeSettings.swift
//  Fabric
//

import Foundation

/// A node's settings as one value: the state its settings view edits that its
/// ports do not hold. A node gives it through `Node.settings` and is brought to
/// it by `Node.apply(_:)`. It is saved flattened into the node's own container,
/// under keys of its own that are not `Node.CodingKeys`, and decoded by the
/// node's `init(from:)`.
public protocol NodeSettings: Codable, Equatable, Sendable { }

extension NodeSettings
{
    public func isEqual(to other: any NodeSettings) -> Bool
    {
        (other as? Self).map { $0 == self } ?? false
    }
}
