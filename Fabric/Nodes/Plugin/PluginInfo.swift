//
//  PluginInfo.swift
//  Fabric
//
//  Created by Claude on 2/6/26.
//

import Foundation

/// Metadata parsed from a plugin's Info.plist.
/// Contains all information needed to identify and describe a loaded plugin.
public struct PluginInfo {
    /// The bundle identifier of the plugin (from CFBundleIdentifier)
    public let id: String

    /// The bundle name (from CFBundleName)
    public let name: String

    /// Human-readable display name (from FabricPluginDisplayName, falls back to name)
    public let displayName: String

    /// Version string (from CFBundleShortVersionString)
    public let version: String?

    /// Author name (from FabricPluginAuthor)
    public let author: String?

    /// Description (from FabricPluginDescription)
    public let description: String?

    /// URL to the plugin bundle on disk
    public let bundleURL: URL

    /// The plugin API version this plugin was built for (from FabricPluginAPIVersion)
    public let apiVersion: Int

    /// Array of node class names declared in Info.plist (from FabricPluginNodeClasses)
    public let nodeClassNames: [String]

    /// The loaded Bundle instance
    public let bundle: Bundle

    /// Principal class name if specified (from NSPrincipalClass)
    public let principalClassName: String?

    /// Whether this is an embedded plugin (bundled with Fabric framework).
    /// Embedded plugins have their code already loaded; no bundle loading needed.
    public let isEmbedded: Bool

    /// Initializes PluginInfo by parsing the bundle's Info.plist.
    /// - Parameter bundle: The loaded plugin bundle
    /// - Throws: PluginLoadError if required keys are missing
    public init(bundle: Bundle) throws {
        guard let bundleID = bundle.bundleIdentifier else {
            throw PluginLoadError.missingBundleIdentifier(bundleURL: bundle.bundleURL)
        }

        guard let infoPlist = bundle.infoDictionary else {
            throw PluginLoadError.bundleLoadFailed(
                bundleURL: bundle.bundleURL,
                underlyingError: nil
            )
        }

        // Required: API version
        guard let apiVersion = infoPlist["FabricPluginAPIVersion"] as? Int else {
            throw PluginLoadError.unsupportedAPIVersion(
                pluginID: bundleID,
                foundVersion: nil,
                requiredVersion: PluginLoader.currentAPIVersion
            )
        }

        // Node classes array (can be empty if principal class provides them)
        let nodeClasses = infoPlist["FabricPluginNodeClasses"] as? [String] ?? []
        let hasPrincipalClass = infoPlist["NSPrincipalClass"] != nil

        // Must have either node classes declared OR a principal class that can provide them
        if nodeClasses.isEmpty && !hasPrincipalClass {
            throw PluginLoadError.noNodeClassesDeclared(pluginID: bundleID)
        }

        self.id = bundleID
        self.name = infoPlist["CFBundleName"] as? String ?? bundleID
        self.displayName = infoPlist["FabricPluginDisplayName"] as? String ?? self.name
        self.version = infoPlist["CFBundleShortVersionString"] as? String
        self.author = infoPlist["FabricPluginAuthor"] as? String
        self.description = infoPlist["FabricPluginDescription"] as? String
        self.bundleURL = bundle.bundleURL
        self.apiVersion = apiVersion
        self.nodeClassNames = nodeClasses
        self.bundle = bundle
        self.principalClassName = infoPlist["NSPrincipalClass"] as? String
        self.isEmbedded = infoPlist["FabricPluginEmbedded"] as? Bool ?? false
    }
}
