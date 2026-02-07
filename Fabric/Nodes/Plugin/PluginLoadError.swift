//
//  PluginLoadError.swift
//  Fabric
//
//  Created by Claude on 2/6/26.
//

import Foundation

/// Errors that can occur during plugin loading.
public enum PluginLoadError: Error, LocalizedError {
    /// The bundle failed to load
    case bundleLoadFailed(bundleURL: URL, underlyingError: Error?)

    /// The bundle is missing a CFBundleIdentifier
    case missingBundleIdentifier(bundleURL: URL)

    /// The bundle's Info.plist doesn't declare any node classes in FabricPluginNodeClasses
    case noNodeClassesDeclared(pluginID: String)

    /// The plugin's FabricPluginAPIVersion is incompatible with this version of Fabric
    case unsupportedAPIVersion(pluginID: String, foundVersion: Int?, requiredVersion: Int)

    /// A declared node class could not be found in the plugin bundle
    case classNotFound(pluginID: String, className: String)

    /// A declared class exists but is not a subclass of Node
    case classNotNodeSubclass(pluginID: String, className: String)

    /// A node with the same name is already registered (either by another plugin or built-in)
    case duplicateNodeName(pluginID: String, nodeName: String, existingSource: String)

    /// The NSPrincipalClass was declared but could not be loaded
    case principalClassLoadFailed(pluginID: String, className: String)

    public var errorDescription: String? {
        switch self {
        case .bundleLoadFailed(let url, let error):
            let base = "Failed to load plugin bundle at \(url.path)"
            if let error = error {
                return "\(base): \(error.localizedDescription)"
            }
            return base

        case .missingBundleIdentifier(let url):
            return "Plugin bundle at \(url.path) is missing CFBundleIdentifier"

        case .noNodeClassesDeclared(let pluginID):
            return "Plugin '\(pluginID)' does not declare any node classes in FabricPluginNodeClasses"

        case .unsupportedAPIVersion(let pluginID, let found, let required):
            if let found = found {
                return "Plugin '\(pluginID)' requires API version \(found), but Fabric supports version \(required)"
            }
            return "Plugin '\(pluginID)' is missing FabricPluginAPIVersion (required: \(required))"

        case .classNotFound(let pluginID, let className):
            return "Plugin '\(pluginID)' declares class '\(className)' but it could not be found"

        case .classNotNodeSubclass(let pluginID, let className):
            return "Plugin '\(pluginID)' declares class '\(className)' but it is not a subclass of Node"

        case .duplicateNodeName(let pluginID, let nodeName, let existingSource):
            return "Plugin '\(pluginID)' declares node '\(nodeName)' but a node with that name already exists in \(existingSource)"

        case .principalClassLoadFailed(let pluginID, let className):
            return "Plugin '\(pluginID)' declares principal class '\(className)' but it could not be loaded"
        }
    }
}
