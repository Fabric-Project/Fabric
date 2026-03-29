//
//  PortRenameAlert.swift
//  Fabric
//
//  Created by Claude on 3/29/26.
//

import SwiftUI

/// ViewModifier that owns the rename alert state for a published port.
///
/// Encapsulates isRenaming and renameText so port views don't carry
/// rename-specific state, and the alert + onChange logic isn't duplicated
/// across NodeInletView and NodeOutletView.
struct PortRenameAlert: ViewModifier
{
    let port: Port
    let graph: Graph

    @State private var isRenaming = false
    @State private var renameText = ""

    func body(content: Content) -> some View
    {
        content
            .contextMenu { PortContextMenu(port: port, graph: graph, isRenaming: $isRenaming) }
            .alert("Rename Published Port", isPresented: $isRenaming) {
                TextField("Published name", text: $renameText)
                Button("OK", action: commitRename)
                Button("Clear", role: .destructive, action: clearName)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter a custom name for this published port, or clear to use the default.")
            }
            .onChange(of: isRenaming) {
                if isRenaming {
                    renameText = graph.publishedName(for: port)
                }
            }
    }

    private func commitRename()
    {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        graph.setPublishedName(trimmed.isEmpty ? nil : trimmed, for: port)
    }

    private func clearName()
    {
        graph.setPublishedName(nil, for: port)
    }
}
