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

    // As NodeStatusIconView colours the glyph.
    private var color: Color
    {
        switch status
        {
        case .error:   .red
        case .warning: .yellow
        }
    }

    var body: some View
    {
        Text(status.message)
            .font(.system(size: 10))
            .foregroundStyle(color)
    }
}
