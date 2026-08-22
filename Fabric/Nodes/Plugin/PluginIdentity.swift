//
//  PluginIdentity.swift
//  Fabric
//
//  Created by Anton Marini on 7/27/26.
//

import Foundation

public struct PluginQualifiedNodeID: Codable, Hashable, Sendable, CustomStringConvertible
{
    public static let separator = "/"

    public let pluginID: String
    public let nodeID: String

    public init(pluginID: String, nodeID: String)
    {
        self.pluginID = pluginID
        self.nodeID = nodeID
    }

    public var description: String
    {
        "\(pluginID)\(Self.separator)\(nodeID)"
    }
}

public struct PluginRequirement: Codable, Hashable, Sendable
{
    public let id: String
    public let version: String?

    public init(id: String, version: String? = nil)
    {
        self.id = id
        self.version = version
    }
}
