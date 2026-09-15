//
//  NodeTitleIcon.swift
//  Fabric
//
//  Created by Claude on 9/9/26.
//

import Foundation

/// A glyph a node shows at the trailing edge of its title row, with a
/// tooltip on the row: a parse error, a link to something outside the node.
/// Nodes derive one through `Node.deriveTitleIcon()`.
public struct NodeTitleIcon: Equatable
{
    /// How the glyph is coloured against the title band.
    public enum Tint: Equatable
    {
        /// Reads as part of the title.
        case neutral
        /// Something to look at.
        case warning
        /// Something broken.
        case error
    }

    public let systemName: String
    public let tooltip: String
    public let tint: Tint

    public init(systemName: String, tooltip: String, tint: Tint = .neutral)
    {
        self.systemName = systemName
        self.tooltip = tooltip
        self.tint = tint
    }
}
