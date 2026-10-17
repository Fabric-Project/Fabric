//
//  PluginInfo.swift
//  Fabric
//
//  Created by Anton Marini on 7/24/26.
//

import Foundation
import os

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

    /// The plugin's Sparkle feed (`SUFeedURL`). Non-nil only when the feed is
    /// https and `SUPublicEDKey` is also present, so a half-configured plugin
    /// reads as not opted in to updates. Fabric does not act on it; a host
    /// chooses its own update mechanism.
    public let updateFeedURL: URL?
    /// The plugin's Sparkle EdDSA public key (`SUPublicEDKey`).
    public let updatePublicEDKey: String?
    /// The plugin's `SUEnableAutomaticChecks`, or nil when it does not say.
    public let automaticallyChecksForUpdates: Bool?

    public var supportsUpdates: Bool
    {
        updateFeedURL != nil
    }

    private static let logger = Logger(subsystem: "graphics.fabric", category: "PluginInfo")

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
                bundle: Bundle,
                updateFeedURL: URL? = nil,
                updatePublicEDKey: String? = nil,
                automaticallyChecksForUpdates: Bool? = nil)
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
        self.updateFeedURL = updateFeedURL
        self.updatePublicEDKey = updatePublicEDKey
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
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

        let feedURLString = infoDictionary["SUFeedURL"] as? String
        let publicEDKey = (infoDictionary["SUPublicEDKey"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let feedURL = feedURLString.flatMap { URL(string: $0) }

        if feedURL?.scheme?.lowercased() == "https", let publicEDKey
        {
            self.updateFeedURL = feedURL
            self.updatePublicEDKey = publicEDKey
        }
        else
        {
            if feedURLString != nil || publicEDKey != nil
            {
                Self.logger.notice("Plugin '\(bundleID, privacy: .public)' is not opted in to updates: SUFeedURL must be an https URL and SUPublicEDKey must be set")
            }
            self.updateFeedURL = nil
            self.updatePublicEDKey = nil
        }

        self.automaticallyChecksForUpdates = infoDictionary["SUEnableAutomaticChecks"] as? Bool
    }
}
