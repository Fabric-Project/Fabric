//
//  CheckForPluginUpdatesView.swift
//  Fabric
//
//  Created by Anton Marini on 10/17/26.
//

import SwiftUI

/// One menu item that checks every plugin opted in to updates. Absent when no
/// loaded plugin has opted in.
struct CheckForPluginUpdatesView: View {
    let pluginUpdateController: PluginUpdateController

    var body: some View {
        if !pluginUpdateController.pluginUpdaters.isEmpty
        {
            Button("Check for Plugin Updates…", action: pluginUpdateController.checkForUpdates)
                .disabled(!pluginUpdateController.canCheckForUpdates)
        }
    }
}
