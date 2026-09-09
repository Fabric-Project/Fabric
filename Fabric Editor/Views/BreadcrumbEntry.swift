//
//  BreadcrumbEntry.swift
//  Fabric Editor
//
//  Created by Claude on 9/9/26.
//

import SwiftUI
import Fabric

/// A breadcrumb entry: the subgraph node's title, preceded by its title icon
/// where it has one (a clone set member's glyph), with the icon's tooltip on
/// hover, the same way the node shows it on the canvas.
struct BreadcrumbEntry: View
{
    let node: SubgraphNode
    let nodeViewModel: NodeViewModel?
    let action: () -> Void

    var body: some View
    {
        let titleIcon = nodeViewModel?.titleIcon

        Button(action: action)
        {
            HStack(spacing: 4)
            {
                if let titleIcon
                {
                    Image(systemName: titleIcon.systemName)
                }
                Text(node.title)
            }
        }
        .font(.headline)
        .buttonStyle(.plain)
        .help(titleIcon?.tooltip ?? "")
    }
}
