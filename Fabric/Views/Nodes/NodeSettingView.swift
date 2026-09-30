//
//  NodeSettingView.swift
//  Fabric
//

import SwiftUI

/// The standard chrome wrapper shown around a node's custom settings view.
/// Displays the node's type name as a header, a close button, and delegates the
/// content to NodeViewModel.settingsView().
struct NodeSettingView: View
{
    @Bindable var nodeViewModel: NodeViewModel

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

            // The wrapper owns sizing: every node's settings content gets the
            // same small controls and matching text, and sits directly under
            // the header. Settings content sets neither itself.
            if nodeViewModel.providesSettingsView()
            {
                nodeViewModel.settingsView()
                    .controlSize(.small)
                    .font(.subheadline)
            }

            Spacer()
        }
        .padding()
        .frame(width: size.width, height: size.height)
        .clipShape(
            RoundedRectangle(cornerRadius: 4)
        )
    }
}
