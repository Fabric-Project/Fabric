//
//  PluginLoadError.swift
//  Fabric
//
//  Created by Anton Marini on 7/24/26.
//

import Foundation

/// Errors that can occur while discovering and loading Fabric plugin bundles.
public enum PluginLoadError: FabricErrorProtocol
{
    case bundleNotFound(bundleURL: URL)
    case bundleLoadFailed(bundleURL: URL, underlyingError: Error?)
    case missingBundleIdentifier(bundleURL: URL)
    case noNodeClassesDeclared(pluginID: String)
    case unsupportedAPIVersion(pluginID: String, foundVersion: Int?, supportedVersion: Int)
    case classNotFound(pluginID: String, className: String)
    case classNotNodeSubclass(pluginID: String, className: String)
    case principalClassLoadFailed(pluginID: String, className: String)
    case duplicatePluginIdentifier(pluginID: String)
    case duplicateNodeName(pluginID: String, nodeName: String, existingSource: String)

    public var severity: FabricErrorSeverity
    {
        .recoverable
    }

    public var errorDescription: String?
    {
        switch self
        {
        case .bundleNotFound(let bundleURL):
            "Plugin bundle was not found at \(bundleURL.path)"
        case .bundleLoadFailed(let bundleURL, let underlyingError):
            if let underlyingError
            {
                "Failed to load plugin bundle at \(bundleURL.path): \(underlyingError.localizedDescription)"
            }
            else
            {
                "Failed to load plugin bundle at \(bundleURL.path)"
            }
        case .missingBundleIdentifier(let bundleURL):
            "Plugin bundle at \(bundleURL.path) is missing CFBundleIdentifier"
        case .noNodeClassesDeclared(let pluginID):
            "Plugin '\(pluginID)' does not declare node classes or a principal class"
        case .unsupportedAPIVersion(let pluginID, let foundVersion, let supportedVersion):
            if let foundVersion
            {
                "Plugin '\(pluginID)' targets API version \(foundVersion), but Fabric supports \(supportedVersion)"
            }
            else
            {
                "Plugin '\(pluginID)' is missing FabricPluginAPIVersion"
            }
        case .classNotFound(let pluginID, let className):
            "Plugin '\(pluginID)' declares node class '\(className)', but that class could not be found"
        case .classNotNodeSubclass(let pluginID, let className):
            "Plugin '\(pluginID)' declares class '\(className)', but it is not a Node subclass"
        case .principalClassLoadFailed(let pluginID, let className):
            "Plugin '\(pluginID)' declares principal class '\(className)', but it could not be loaded"
        case .duplicatePluginIdentifier(let pluginID):
            "Plugin '\(pluginID)' is already loaded"
        case .duplicateNodeName(let pluginID, let nodeName, let existingSource):
            "Plugin '\(pluginID)' declares node '\(nodeName)', but that node already exists in \(existingSource)"
        }
    }
}
