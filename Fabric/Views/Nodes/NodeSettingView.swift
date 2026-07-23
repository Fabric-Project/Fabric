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
                Text("\(type(of: nodeViewModel.node).name) Settings")
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
            }
        }
        .padding()
        .frame(width: size.width, height: size.height)
        .clipShape(
            RoundedRectangle(cornerRadius: 4)
        )
    }
}
