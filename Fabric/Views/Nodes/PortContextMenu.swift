//
//  PortContextMenu.swift
//  Fabric
//
//  Created by Claude on 3/29/26.
//

import SwiftUI

/// Context menu for inlet and outlet port views.
///
/// Extracted as a dedicated View struct so SwiftUI can track its
/// invalidation independently from the port view's drag/render state,
/// avoiding unnecessary body re-evaluations during canvas interaction.
struct PortContextMenu: View
{
    let port: Port
    let graph: Graph
    @Binding var isRenaming: Bool

    var body: some View
    {
        Button(action: publish) {
            Text(graph.isPublished(port) ? "Unpublish" : "Publish")
        }

        if graph.isPublished(port) {
            Button(action: rename) {
                Text("Rename…")
            }
        }

        if !port.connections.isEmpty {
            Button(action: disconnect) {
                Text("Disconnect")
            }
        }
    }

    private func publish()
    {
        graph.togglePublished(port: port)
    }

    private func rename()
    {
        isRenaming = true
    }

    private func disconnect()
    {
        port.disconnectAll()
        graph.shouldUpdateConnections.toggle()
    }
}
