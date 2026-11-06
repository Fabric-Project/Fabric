//
//  PluginUpdater.swift
//  Fabric
//
//  Created by Anton Marini on 10/17/26.
//

import Foundation
import Fabric
import Sparkle

/// One plugin's Sparkle updater. The plugin bundle is the updater's host, so
/// Sparkle reads the plugin's own feed, key and version, and installs over the
/// plugin bundle; the editor is only the application it relaunches.
@MainActor
final class PluginUpdater
{
    let pluginInfo: PluginInfo
    let updater: SPUUpdater

    // SPUUpdater does not retain its user driver.
    private let userDriver: SPUStandardUserDriver

    init(pluginInfo: PluginInfo) throws
    {
        self.pluginInfo = pluginInfo
        self.userDriver = SPUStandardUserDriver(hostBundle: pluginInfo.bundle, delegate: nil)
        self.updater = SPUUpdater(hostBundle: pluginInfo.bundle,
                                  applicationBundle: .main,
                                  userDriver: self.userDriver,
                                  delegate: nil)

        // Loaded plugin code cannot be unloaded, so updates download in the
        // background and install when the editor quits.
        self.updater.automaticallyDownloadsUpdates = true

        try self.updater.start()
    }
}
