//
//  NodeSettingView.swift
//  Fabric
//

import SwiftUI

/// The standard chrome wrapper shown around a node's custom settings view.
/// Displays the node's type name as a header, a close button, and delegates the
/// content to NodeViewModel.settingsView(). While it is shown, what the node's
/// settings view edits is recorded for undo; see NodeSettingsSession.
struct NodeSettingView: View
{
    @Bindable var nodeViewModel: NodeViewModel
    @State private var session: NodeSettingsSession?
    @State private var restoreCount = 0

    var body: some View
    {
        let size = nodeViewModel.settingsSize.size()

        VStack(alignment: .center)
        {
            HStack()
            {
                Text("\(nodeViewModel.title) Settings")
                    .lineLimit(1)
                    .font(.system(size: 10))
                    .bold()

                Spacer()

                Button("Close", systemImage: "x.circle") {
                    nodeViewModel.showSettings = false
                }
                .controlSize(.small)
            }

            Spacer()

            if nodeViewModel.providesSettingsView()
            {
                nodeViewModel.settingsView()
                    .id(restoreCount)
            }
        }
        .padding()
        .frame(width: size.width, height: size.height)
        .clipShape(
            RoundedRectangle(cornerRadius: 4)
        )
        .onAppear { session = NodeSettingsSession(node: nodeViewModel.node) }
        .onReceive(nodeViewModel.node.settingsRestoredSubject) { restoreCount += 1 }
        .onDisappear {
            session?.end()
            session = nil
        }
    }
}
