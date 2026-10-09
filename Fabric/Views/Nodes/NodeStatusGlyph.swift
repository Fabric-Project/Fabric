//
//  NodeStatusGlyph.swift
//  Fabric
//
//  Created by Claude on 9/11/26.
//

import SwiftUI

/// How each node status looks, for every place that draws one: the node
/// title, the editor's breadcrumb. The node reports the meaning; this is
/// where it becomes a glyph and a colour.
public enum NodeStatusGlyph
{
    public static func symbolName(for status: NodeStatus) -> String
    {
        switch status
        {
        case .error:   "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .linked:  "square.on.square"
        }
    }

    public static func color(for status: NodeStatus) -> Color
    {
        switch status
        {
        case .error:   .red
        case .warning: .yellow
        case .linked:  .white
        }
    }

    /// Every status's line, most severe first, for a tooltip.
    public static func tooltip(for statuses: [NodeStatus]) -> String
    {
        statuses.map(\.description).joined(separator: "\n")
    }
}
