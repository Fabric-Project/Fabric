//
//  PluginLoader.swift
//  Fabric
//
//  Created by Anton Marini on 7/24/26.
//

import Foundation
import os

/// Loads Fabric's embedded core plugin plus optional external node plugin bundles.
public final class PluginLoader
{
    public static let shared = PluginLoader()
    public static let currentAPIVersion = 1
    public static let pluginExtension = "fabricplugin"
    public static let coreNodesPluginID = FabricCoreNodesPlugin.pluginID

    public private(set) var loadedPlugins: [String: PluginInfo] = [:]
    public private(set) var pluginNodeClasses: [PluginQualifiedNodeID: Node.Type] = [:]
    public private(set) var pluginNodeWrappers: [NodeClassWrapper] = []
    public private(set) var loadErrors: [PluginLoadError] = []

    private var nodeIDAliases: [PluginQualifiedNodeID: PluginQualifiedNodeID] = [:]
    private let logger = Logger(subsystem: "graphics.fabric", category: "PluginLoader")
    private var pluginsLoaded = false
    private let pluginLoadLock = NSRecursiveLock()

    private init() {}

    public func pluginSearchDirectories() -> [URL]
    {
        var directories: [URL] = []

        if let builtInPlugInsURL = Bundle.main.builtInPlugInsURL
        {
            directories.append(builtInPlugInsURL)
        }

        if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        {
            directories.append(appSupportURL
                .appending(path: "Fabric", directoryHint: .isDirectory)
                .appending(path: "Plugins", directoryHint: .isDirectory))
        }

        #if os(macOS)
        directories.append(URL(filePath: "  ", directoryHint: .isDirectory))
        #endif

        return directories
    }

    public func discoverPlugins() throws -> [URL]
    {
        var pluginURLs: [URL] = []
        let fileManager = FileManager.default

        for directory in pluginSearchDirectories()
        {
            guard fileManager.fileExists(atPath: directory.path) else { continue }

            do
            {
                let contents = try fileManager.contentsOfDirectory(at: directory,
                                                                    includingPropertiesForKeys: [.isDirectoryKey],
                                                                    options: [.skipsHiddenFiles])
                pluginURLs.append(contentsOf: contents.filter { $0.pathExtension == Self.pluginExtension })
            }
            catch
            {
                throw PluginLoadError.pluginDirectoryScanFailed(directoryURL: directory,
                                                               underlyingError: error)
            }
        }

        return pluginURLs
    }

    public func loadAllPlugins() throws
    {
        pluginLoadLock.lock()
        defer { pluginLoadLock.unlock() }

        guard !pluginsLoaded else { return }
        pluginsLoaded = true

        loadErrors.removeAll()
        do
        {
            try loadEmbeddedCorePlugin()
            try loadDiscoveredPlugins()
        }
        catch
        {
            pluginsLoaded = false
            throw error
        }
    }

    public func loadDiscoveredPlugins() throws
    {
        let existingNodeNames = currentRegisteredNodeNames()

        let pluginURLs: [URL]
        pluginURLs = try discoverPlugins()

        logger.info("Found \(pluginURLs.count) Fabric plugin bundle(s)")

        for pluginURL in pluginURLs
        {
            do
            {
                try loadPlugin(at: pluginURL, existingNodeNames: existingNodeNames)
            }
            catch let error as PluginLoadError
            {
                loadErrors.append(error)
                logger.error("\(error.localizedDescription)")
                throw error
            }
            catch
            {
                let wrappedError = PluginLoadError.bundleLoadFailed(bundleURL: pluginURL, underlyingError: error)
                loadErrors.append(wrappedError)
                logger.error("\(wrappedError.localizedDescription)")
                throw wrappedError
            }
        }
    }

    private func loadEmbeddedCorePlugin() throws
    {
        guard loadedPlugins[Self.coreNodesPluginID] == nil else { return }

        let bundle = Bundle.module
        // Core nodes are compiled into Fabric so Swift Package consumers only
        // need to depend on the Fabric product. Registration still flows
        // through the same plugin loader path as external bundles.
        let pluginInfo = PluginInfo(id: Self.coreNodesPluginID,
                                    name: "FabricCoreNodes",
                                    displayName: "Fabric Core Nodes",
                                    version: nil,
                                    author: "Fabric",
                                    description: "Built-in Fabric nodes",
                                    bundleURL: bundle.bundleURL,
                                    apiVersion: Self.currentAPIVersion,
                                    nodeClassNames: [],
                                    principalClassName: String(describing: FabricCoreNodesPlugin.self),
                                    bundle: bundle)

        FabricCoreNodesPlugin.pluginDidLoad(bundle: bundle)

        do
        {
            for nodeClass in FabricCoreNodesPlugin.additionalNodeClasses()
            {
                try registerNodeClass(nodeClass,
                                      pluginID: Self.coreNodesPluginID,
                                      existingNodeNames: [])
            }

            try registerNodeClass(BaseImageNode.self,
                                  pluginID: Self.coreNodesPluginID,
                                  existingNodeNames: [],
                                  includeWrapper: false)
            try registerNodeClass(BaseTextureComputeProcessorNode.self,
                                  pluginID: Self.coreNodesPluginID,
                                  existingNodeNames: [],
                                  includeWrapper: false)

            pluginNodeWrappers.append(contentsOf: FabricCoreNodesPlugin.dynamicNodeWrappers())
            loadedPlugins[Self.coreNodesPluginID] = pluginInfo
            logger.info("Loaded embedded Fabric core nodes plugin")
        }
        catch let error as PluginLoadError
        {
            loadErrors.append(error)
            logger.error("\(error.localizedDescription)")
            throw error
        }
        catch
        {
            let wrappedError = PluginLoadError.bundleLoadFailed(bundleURL: bundle.bundleURL, underlyingError: error)
            loadErrors.append(wrappedError)
            logger.error("\(wrappedError.localizedDescription)")
            throw wrappedError
        }
    }

    public func loadPlugin(at url: URL, existingNodeNames: Set<String>) throws
    {
        guard FileManager.default.fileExists(atPath: url.path) else
        {
            throw PluginLoadError.bundleNotFound(bundleURL: url)
        }

        guard let bundle = Bundle(url: url) else
        {
            throw PluginLoadError.bundleLoadFailed(bundleURL: url, underlyingError: nil)
        }

        let pluginInfo = try PluginInfo(bundle: bundle)

        guard pluginInfo.apiVersion == Self.currentAPIVersion else
        {
            throw PluginLoadError.unsupportedAPIVersion(pluginID: pluginInfo.id,
                                                        foundVersion: pluginInfo.apiVersion,
                                                        supportedVersion: Self.currentAPIVersion)
        }

        guard loadedPlugins[pluginInfo.id] == nil else
        {
            throw PluginLoadError.duplicatePluginIdentifier(pluginID: pluginInfo.id)
        }

        do
        {
            try bundle.loadAndReturnError()
        }
        catch
        {
            throw PluginLoadError.bundleLoadFailed(bundleURL: url, underlyingError: error)
        }

        let principalClass = try loadPrincipalClass(from: pluginInfo)
        principalClass?.pluginDidLoad(bundle: bundle)

        var nodeClasses: [Node.Type] = []

        for className in pluginInfo.nodeClassNames
        {
            nodeClasses.append(try loadNodeClass(className: className, pluginID: pluginInfo.id))
        }

        nodeClasses.append(contentsOf: principalClass?.additionalNodeClasses() ?? [])

        for nodeClass in nodeClasses
        {
            try registerNodeClass(nodeClass,
                                  pluginID: pluginInfo.id,
                                  existingNodeNames: existingNodeNames)
        }

        loadedPlugins[pluginInfo.id] = pluginInfo
        logger.info("Loaded Fabric plugin '\(pluginInfo.displayName)' with \(nodeClasses.count) node class(es)")
    }

    public func nodeClass(pluginID: String, nodeID: String) -> Node.Type?
    {
        let requestedID = PluginQualifiedNodeID(pluginID: pluginID, nodeID: nodeID)
        let resolvedID = nodeIDAliases[requestedID] ?? requestedID
        return pluginNodeClasses[resolvedID]
    }

    public func pluginID(for nodeClass: Node.Type) -> String?
    {
        pluginNodeClasses.first { ObjectIdentifier($0.value) == ObjectIdentifier(nodeClass) }?.key.pluginID
    }

    public func qualifiedNodeID(for nodeClass: Node.Type) -> PluginQualifiedNodeID?
    {
        pluginNodeClasses.first { ObjectIdentifier($0.value) == ObjectIdentifier(nodeClass) }?.key
    }

    private func loadPrincipalClass(from pluginInfo: PluginInfo) throws -> FabricPlugin.Type?
    {
        guard let principalClassName = pluginInfo.principalClassName else { return nil }

        guard let principalClass = NSClassFromString(principalClassName) as? FabricPlugin.Type else
        {
            throw PluginLoadError.principalClassLoadFailed(pluginID: pluginInfo.id, className: principalClassName)
        }

        return principalClass
    }

    private func loadNodeClass(className: String, pluginID: String) throws -> Node.Type
    {
        guard let loadedClass = NSClassFromString(className) else
        {
            throw PluginLoadError.classNotFound(pluginID: pluginID, className: className)
        }

        guard let nodeClass = loadedClass as? Node.Type else
        {
            throw PluginLoadError.classNotNodeSubclass(pluginID: pluginID, className: className)
        }

        return nodeClass
    }

    private func registerNodeClass(_ nodeClass: Node.Type,
                                   pluginID: String,
                                   existingNodeNames: Set<String>,
                                   includeWrapper: Bool = true) throws
    {
        let lookupName = String(describing: nodeClass)
        let nodeID = Self.rootNodeID(from: lookupName)
        let qualifiedNodeID = PluginQualifiedNodeID(pluginID: pluginID, nodeID: nodeID)

        if pluginNodeClasses[qualifiedNodeID] != nil
        {
            throw PluginLoadError.duplicateNodeName(pluginID: pluginID,
                                                    nodeName: nodeID,
                                                    existingSource: "plugin '\(pluginID)'")
        }

        if existingNodeNames.contains(qualifiedNodeID.description)
        {
            throw PluginLoadError.duplicateNodeName(pluginID: pluginID,
                                                    nodeName: nodeID,
                                                    existingSource: "previously registered nodes")
        }

        pluginNodeClasses[qualifiedNodeID] = nodeClass

        if includeWrapper
        {
            pluginNodeWrappers.append(NodeClassWrapper(nodeClass: nodeClass,
                                                       nodeType: nodeClass.nodeType,
                                                       pluginBundleID: pluginID))
        }

        if lookupName != nodeID
        {
            nodeIDAliases[PluginQualifiedNodeID(pluginID: pluginID, nodeID: lookupName)] = qualifiedNodeID
        }

        logger.debug("Registered node class '\(qualifiedNodeID.description)'")
    }

    private func currentRegisteredNodeNames() -> Set<String>
    {
        Set(pluginNodeClasses.keys.map(\.description))
    }

    private static func rootNodeID(from className: String) -> String
    {
        if let genericStart = className.firstIndex(of: "<")
        {
            let baseName = className[..<genericStart]
            let genericSuffix = className[genericStart...]
            let rootBaseName = baseName.split(separator: ".").last ?? baseName[...]
            return "\(rootBaseName)\(genericSuffix)"
        }

        return String(className.split(separator: ".").last ?? Substring(className))
    }
}
