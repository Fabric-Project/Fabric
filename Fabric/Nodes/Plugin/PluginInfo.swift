//
//  PluginInfo.swift
//  Fabric
//
//  Created by Anton Marini on 7/24/26.
//

import Foundation

/// Metadata parsed from a Fabric plugin bundle's Info.plist.
public struct PluginInfo
{
    public let id: String
    public let name: String
    public let displayName: String
    public let version: String?
    public let author: String?
    public let description: String?
    public let bundleURL: URL
    public let apiVersion: Int
    public let nodeClassNames: [String]
    public let principalClassName: String?
    public let bundle: Bundle

    public init(id: String,
                name: String,
                displayName: String,
                version: String? = nil,
                author: String? = nil,
                description: String? = nil,
                bundleURL: URL,
                apiVersion: Int,
                nodeClassNames: [String],
                principalClassName: String?,
                bundle: Bundle)
    {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.version = version
        self.author = author
        self.description = description
        self.bundleURL = bundleURL
        self.apiVersion = apiVersion
        self.nodeClassNames = nodeClassNames
        self.principalClassName = principalClassName
        self.bundle = bundle
    }

    public init(bundle: Bundle) throws
    {
        guard let bundleID = bundle.bundleIdentifier else
        {
            throw PluginLoadError.missingBundleIdentifier(bundleURL: bundle.bundleURL)
        }

        guard let infoDictionary = bundle.infoDictionary else
        {
            throw PluginLoadError.bundleLoadFailed(bundleURL: bundle.bundleURL, underlyingError: nil)
        }

        guard let apiVersion = infoDictionary["FabricPluginAPIVersion"] as? Int else
        {
            throw PluginLoadError.unsupportedAPIVersion(pluginID: bundleID,
                                                        foundVersion: nil,
                                                        supportedVersion: PluginLoader.currentAPIVersion)
        }

        let nodeClassNames = infoDictionary["FabricPluginNodeClasses"] as? [String] ?? []
        let principalClassName = infoDictionary["NSPrincipalClass"] as? String

        guard !nodeClassNames.isEmpty || principalClassName != nil else
        {
            throw PluginLoadError.noNodeClassesDeclared(pluginID: bundleID)
        }

        self.id = bundleID
        self.name = infoDictionary["CFBundleName"] as? String ?? bundleID
        self.displayName = infoDictionary["FabricPluginDisplayName"] as? String ?? self.name
        self.version = infoDictionary["CFBundleShortVersionString"] as? String
        self.author = infoDictionary["FabricPluginAuthor"] as? String
        self.description = infoDictionary["FabricPluginDescription"] as? String
        self.bundleURL = bundle.bundleURL
        self.apiVersion = apiVersion
        self.nodeClassNames = nodeClassNames
        self.principalClassName = principalClassName
        self.bundle = bundle
    }
}
