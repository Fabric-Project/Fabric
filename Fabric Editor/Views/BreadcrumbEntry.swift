//
//  BreadcrumbEntry.swift
//  Fabric Editor
//
//  Created by Claude on 9/9/26.
//

import SwiftUI
import Fabric

/// A breadcrumb entry: the subgraph node's title, preceded by the glyph of
/// its most severe status where it has one (a clone set member's link),
/// with every status on hover, the same way the node shows them on the canvas.
struct BreadcrumbEntry: View
{
    let node: SubgraphNode
    let nodeViewModel: NodeViewModel?
    let action: () -> Void

    var body: some View
    {
        let statuses = nodeViewModel?.statuses ?? []

        Button(action: action)
        {
            HStack
            {
                if let mostSevere = statuses.first
                {
                    Image(systemName: NodeStatusGlyph.symbolName(for: mostSevere))
                        .help(NodeStatusGlyph.tooltip(for: statuses))
                }
                Text(node.title)
            }
        }
        .font(.headline)
        .buttonStyle(.plain)
    }
}
