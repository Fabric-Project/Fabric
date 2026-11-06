//
//  PluginUpdateController.swift
//  Fabric
//
//  Created by Anton Marini on 10/17/26.
//

import Foundation
import Combine
import Fabric
import os

/// Keeps a Sparkle updater for every loaded plugin that opts in to updates.
///
/// A plugin opts in with `SUFeedURL` and `SUPublicEDKey` in its Info.plist.
/// The core plugin, and plugins inside the editor's own `PlugIns` folder, are
/// skipped: they update with the editor, and changing the app bundle would
/// break its signature. Copies that lost to a higher-precedence copy are not
/// in `loadedPlugins`, so they are skipped too.
@MainActor
@Observable
final class PluginUpdateController
{
    private(set) var pluginUpdaters: [PluginUpdater] = []

    /// True when any plugin's updater can check right now.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private var canCheckSubscription: AnyCancellable?
    @ObservationIgnored private let logger = Logger(subsystem: "graphics.fabric", category: "PluginUpdateController")

    func startUpdaters()
    {
        guard pluginUpdaters.isEmpty else { return }

        // Plugins load lazily on first registry use; make sure they have.
        // Load failures are surfaced through NodeRegistry.pluginLoadErrors.
        _ = try? NodeRegistry.shared

        let updatablePlugins = PluginLoader.shared.loadedPlugins.values
            .filter { $0.supportsUpdates }
            .filter { $0.id != PluginLoader.coreNodesPluginID }
            .filter { !Self.isInsideBuiltInPlugInsFolder($0.bundleURL) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

        var pluginUpdaters: [PluginUpdater] = []

        for pluginInfo in updatablePlugins
        {
            do
            {
                pluginUpdaters.append(try PluginUpdater(pluginInfo: pluginInfo))
            }
            catch
            {
                logger.error("Could not start updates for plugin '\(pluginInfo.id, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }

        self.pluginUpdaters = pluginUpdaters

        canCheckSubscription = Publishers.MergeMany(pluginUpdaters.map { $0.updater.publisher(for: \.canCheckForUpdates) })
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.canCheckForUpdates = self.pluginUpdaters.contains { $0.updater.canCheckForUpdates }
            }
    }

    /// Checks every opted-in plugin. Each plugin's standard user driver shows
    /// its own result.
    func checkForUpdates()
    {
        for pluginUpdater in pluginUpdaters where pluginUpdater.updater.canCheckForUpdates
        {
            pluginUpdater.updater.checkForUpdates()
        }
    }

    private static func isInsideBuiltInPlugInsFolder(_ bundleURL: URL) -> Bool
    {
        guard let builtInPlugInsURL = Bundle.main.builtInPlugInsURL else { return false }

        let folderComponents = builtInPlugInsURL.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let bundleComponents = bundleURL.standardizedFileURL.resolvingSymlinksInPath().pathComponents

        return bundleComponents.starts(with: folderComponents)
    }
}
