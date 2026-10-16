//
//  NodeStatusMessageView.swift
//  Fabric
//

import SwiftUI

/// A node's status as a line of text, coloured as its title glyph is, for
/// settings views that say why a node is not doing its job.
struct NodeStatusMessageView: View
{
    let status: NodeStatus

    var body: some View
    {
        Text(status.message)
            .font(.caption)
            .foregroundStyle(status.color)
    }
}
