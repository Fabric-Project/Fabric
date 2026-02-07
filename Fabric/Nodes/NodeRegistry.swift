//
//  NodeRegistry.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//

import simd
import Foundation

/// Central registry for all available node types in Fabric.
/// Nodes are loaded from plugins (including the built-in FabricCoreNodes plugin).
public class NodeRegistry {

    public static let shared = NodeRegistry()

    /// Whether plugins have been loaded yet
    private var pluginsLoaded = false

    private init() {
        loadPluginsIfNeeded()
    }

    /// Loads plugins if they haven't been loaded yet.
    /// Called automatically during init.
    private func loadPluginsIfNeeded() {
        guard !pluginsLoaded else { return }
        pluginsLoaded = true
        PluginLoader.shared.loadAllPlugins()
    }

    /// Returns the Node.Type for a given node name.
    /// Supports both qualified names (Fabric.NodeName) and legacy unqualified names.
    /// - Parameter nodeName: The name of the node class to look up
    /// - Returns: The Node.Type if found, nil otherwise
    public func nodeClass(for nodeName: String) -> (Node.Type)? {
        // First try direct lookup
        if let nodeClass = PluginLoader.shared.pluginNodeClasses[nodeName]?.nodeClass {
            return nodeClass
        }

        // Try resolving as a legacy alias
        let resolvedName = PluginLoader.shared.resolveClassName(nodeName)
        if resolvedName != nodeName {
            return PluginLoader.shared.pluginNodeClasses[resolvedName]?.nodeClass
        }

        return nil
    }

    /// All available nodes from all loaded plugins.
    /// This includes both Swift class-based nodes and dynamic effect nodes from metal shaders.
    public var availableNodes: [NodeClassWrapper] {
        return PluginLoader.shared.pluginNodeWrappers
    }

    /// Returns all loaded plugins.
    public var loadedPlugins: [String: PluginInfo] {
        return PluginLoader.shared.loadedPlugins
    }

    /// Returns any errors that occurred during plugin loading.
    public var pluginLoadErrors: [PluginLoadError] {
        return PluginLoader.shared.loadErrors
    }
}
