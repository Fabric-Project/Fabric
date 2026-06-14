//
//  NodeSettingView.swift
//  Fabric
//

import SwiftUI

/// The standard chrome wrapper shown around a node's custom settings view.
/// Displays the node's name as a header, a close button, and delegates the
/// content to NodeViewModel.settingsView().
struct NodeSettingView: View
{
    @Bindable var vm: NodeViewModel

    var body: some View
    {
        let size = vm.settingsSize.size()

        VStack(alignment: .center)
        {
            HStack()
            {
                Text("\(vm.name) Settings")
                    .lineLimit(1)
                    .font(.system(size: 10))
                    .bold()

                Spacer()

                Button("Close", systemImage: "x.circle") {
                    vm.showSettings = false
                }
                .controlSize(.small)
            }

            Spacer()

            if vm.providesSettingsView()
            {
                vm.settingsView()
            }
        }
        .padding()
        .frame(width: size.width, height: size.height)
        .clipShape(
            RoundedRectangle(cornerRadius: 4)
        )
    }
}
