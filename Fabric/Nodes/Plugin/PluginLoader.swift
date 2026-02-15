//
//  PluginLoader.swift
//  Fabric
//
//  Created by Claude on 2/6/26.
//

import Foundation
import os.log

/// Singleton that handles discovery and loading of Fabric plugins.
/// Plugins are loaded from .fabricplugin bundles found in standard directories.
internal class PluginLoader
{

    // MARK: - Singleton

    /// Shared instance of the plugin loader
    public static let shared = PluginLoader()

    // MARK: - Constants

    /// Current API version supported by this Fabric build.
    /// Plugins must declare a compatible FabricPluginAPIVersion.
    public static let currentAPIVersion = 1

    /// File extension for Fabric plugin bundles
    public static let pluginExtension = "fabricplugin"

    /// Bundle identifier for the embedded core nodes plugin
    public static let coreNodesPluginID = "info.HiRez.Fabric.CoreNodes"

    // MARK: - State

    /// Dictionary of successfully loaded plugins keyed by bundle identifier
    public private(set) var loadedPlugins: [String: PluginInfo] = [:]

    /// Dictionary of node classes from plugins keyed by node class name.
    /// Contains the Node.Type and the plugin ID that provided it.
    public private(set) var pluginNodeClasses: [String: (nodeClass: Node.Type, pluginID: String)] = [:]

    /// Array of NodeClassWrappers for plugin nodes, ready for use in availableNodes
    public private(set) var pluginNodeWrappers: [NodeClassWrapper] = []

    /// Errors encountered during plugin loading (non-fatal)
    public private(set) var loadErrors: [PluginLoadError] = []

    /// Legacy class name aliases for backward compatibility
    /// Maps old unqualified names to current qualified names
    private var classNameAliases: [String: String] = [:]

    /// Logger for plugin loading operations
    private let logger = Logger(subsystem: "info.HiRez.Fabric", category: "PluginLoader")

    // MARK: - Initialization

    private init() {}

    // MARK: - Discovery

    /// Returns the directories where plugins are searched for.
    /// - Returns: Array of directory URLs to search
    public func pluginSearchDirectories() -> [URL]
    {
        var directories: [URL] = []

        // 1. App-bundled plugins: Fabric.app/Contents/PlugIns/
        if let plugInsURL = Bundle.main.builtInPlugInsURL
        {
            directories.append(plugInsURL)
        }

        // 2. User plugins: ~/Library/Application Support/Fabric/Plugins/
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        {
            let userPlugins = appSupport
                .appendingPathComponent("Fabric", isDirectory: true)
                .appendingPathComponent("Plugins", isDirectory: true)
            
            directories.append(userPlugins)
        }

        // 3. System-wide plugins: /Library/Application Support/Fabric/Plugins/
        let systemPlugins = URL(fileURLWithPath: "/Library/Application Support/Fabric/Plugins", isDirectory: true)
        directories.append(systemPlugins)

        return directories
    }

    /// Discovers all .fabricplugin bundles in the search directories.
    /// - Returns: Array of URLs to discovered plugin bundles
    public func discoverPlugins() -> [URL]
    {
        var pluginURLs: [URL] = []
        let fileManager = FileManager.default

        for directory in pluginSearchDirectories()
        {
            guard fileManager.fileExists(atPath: directory.path) else
            {
                continue
            }
            do
            {
                let contents = try fileManager.contentsOfDirectory(at: directory,
                                                                   includingPropertiesForKeys: [.isDirectoryKey],
                                                                   options: [.skipsHiddenFiles])
                for url in contents
                {
                    if url.pathExtension == Self.pluginExtension
                    {
                        pluginURLs.append(url)
                        self.logger.info("Discovered plugin: \(url.lastPathComponent)")
                    }
                }
            }
            catch
            {
                self.logger.warning("Failed to scan plugin directory \(directory.path): \(error.localizedDescription)")
            }
        }

        return pluginURLs
    }

    // MARK: - Loading

    /// Loads all plugins: first the embedded core plugin, then discovered external plugins.
    /// Errors are collected in loadErrors rather than thrown.
    public func loadAllPlugins()
    {
        // First, load the embedded core nodes plugin
        self.loadEmbeddedCorePlugin()

        // Then load dynamic effect nodes (metal shader-based)
        self.loadDynamicEffectNodes()

        // Finally, discover and load external plugins
        let pluginURLs = self.discoverPlugins()

        self.logger.info("Found \(pluginURLs.count) external plugin(s) to load")

        for url in pluginURLs
        {
            do
            {
                try loadPlugin(at: url)
            }
            catch let error as PluginLoadError
            {
                self.loadErrors.append(error)
                self.logger.error("Failed to load plugin at \(url.path): \(error.localizedDescription)")
            }
            catch
            {
                let wrappedError = PluginLoadError.bundleLoadFailed(bundleURL: url, underlyingError: error)
                self.loadErrors.append(wrappedError)
                self.logger.error("Unexpected error loading plugin at \(url.path): \(error.localizedDescription)")
            }
        }

        self.logger.info("Loaded \(self.loadedPlugins.count) plugin(s), \(self.pluginNodeWrappers.count) node class(es)")
        if !loadErrors.isEmpty
        {
            self.logger.warning("\(self.loadErrors.count) plugin(s) failed to load")
        }
    }

    /// Loads the embedded FabricCoreNodes plugin from the framework bundle.
    private func loadEmbeddedCorePlugin()
    {
        // Use Bundle.module for SwiftPM resource access
        let frameworkBundle = Bundle.module

        // Look for the embedded plugin in the framework's resources
        guard let pluginURL = frameworkBundle.url(forResource: "FabricCoreNodes", withExtension: "fabricplugin")
        else
        {
            self.logger.error("Embedded FabricCoreNodes.fabricplugin not found in framework bundle")
            return
        }

        do
        {
            try loadPlugin(at: pluginURL)
            self.logger.info("Loaded embedded core nodes plugin")
        }
        catch
        {
            self.logger.error("Failed to load embedded core nodes plugin: \(error.localizedDescription)")
        }
    }

    /// Loads dynamic effect nodes from metal shader files.
    /// These are nodes whose behavior is defined by metal shaders rather than Swift classes.
    private func loadDynamicEffectNodes()
    {
        let bundle = Bundle.module

        for imageEffectType in Node.NodeType.ImageType.allCases
        {
            let singleChannelEffects = "Effects/\(imageEffectType.rawValue)"
            let twoChannelEffects = "EffectsTwoChannel/\(imageEffectType.rawValue)"
            let threeChannelEffects = "EffectsThreeChannel/\(imageEffectType.rawValue)"
            let computeSubdir = "Compute/\(imageEffectType.rawValue)"

            if let singleChannelURLs = bundle.urls(forResourcesWithExtension: "metal", subdirectory: singleChannelEffects),
               let twoChannelURLs = bundle.urls(forResourcesWithExtension: "metal", subdirectory: twoChannelEffects),
               let threeChannelURLs = bundle.urls(forResourcesWithExtension: "metal", subdirectory: threeChannelEffects),
               let computeURLs = bundle.urls(forResourcesWithExtension: "metal", subdirectory: computeSubdir)
            {

                for fileURL in singleChannelURLs
                {
                    let baseClass: Node.Type = [.Generator, .ShapeGenerator].contains(imageEffectType) ? BaseGeneratorNode.self : BaseEffectNode.self
                    let wrapper = NodeClassWrapper( nodeClass: baseClass,
                                                    nodeType: .Image(imageType: imageEffectType),
                                                    fileURL: fileURL,
                                                    nodeName: fileURLToName(fileURL: fileURL),
                                                    pluginBundleID: Self.coreNodesPluginID)
                    
                    self.pluginNodeWrappers.append(wrapper)
                }

                for fileURL in twoChannelURLs
                {
                    let wrapper = NodeClassWrapper(nodeClass: BaseEffectTwoChannelNode.self,
                                                   nodeType: .Image(imageType: imageEffectType),
                                                   fileURL: fileURL,
                                                   nodeName: fileURLToName(fileURL: fileURL),
                                                   pluginBundleID: Self.coreNodesPluginID)
                    
                    self.pluginNodeWrappers.append(wrapper)
                }

                for fileURL in threeChannelURLs
                {
                    let wrapper = NodeClassWrapper(nodeClass: BaseEffectThreeChannelNode.self,
                                                   nodeType: .Image(imageType: imageEffectType),
                                                   fileURL: fileURL,
                                                   nodeName: fileURLToName(fileURL: fileURL),
                                                   pluginBundleID: Self.coreNodesPluginID)
                    
                    self.pluginNodeWrappers.append(wrapper)
                }

                for fileURL in computeURLs
                {
                    let wrapper = NodeClassWrapper(nodeClass: BaseTextureComputeProcessorNode.self,
                                                   nodeType: .Image(imageType: imageEffectType),
                                                   fileURL: fileURL,
                                                   nodeName: fileURLToName(fileURL: fileURL),
                                                   pluginBundleID: Self.coreNodesPluginID)

                    self.pluginNodeWrappers.append(wrapper)
                }
            }
        }

        // Sort dynamic nodes by name
        self.pluginNodeWrappers.sort { $0.nodeName < $1.nodeName }

        self.logger.debug("Loaded \(self.pluginNodeWrappers.count) dynamic effect nodes")
    }

    /// Converts a shader file URL to a display name.
    private func fileURLToName(fileURL: URL) -> String
    {
        let nodeName = fileURL.deletingPathExtension().lastPathComponent.replacing("ImageNode", with: "")
        return nodeName.titleCase
    }

    /// Loads a single plugin from the specified URL.
    /// - Parameter url: URL to the .fabricplugin bundle
    /// - Throws: PluginLoadError if loading fails
    public func loadPlugin(at url: URL) throws
    {
        self.logger.info("Loading plugin at \(url.path)")

        // Load the bundle
        guard let bundle = Bundle(url: url)
        else
        {
            throw PluginLoadError.bundleLoadFailed(bundleURL: url, underlyingError: nil)
        }

        // Parse plugin info from Info.plist first to check if embedded
        let pluginInfo = try PluginInfo(bundle: bundle)

        // For non-embedded plugins, actually load the executable code
        if !pluginInfo.isEmbedded
        {
            do
            {
                try bundle.loadAndReturnError()
            }
            catch
            {
                throw PluginLoadError.bundleLoadFailed(bundleURL: url, underlyingError: error)
            }
        }

        // Check API version compatibility
        if pluginInfo.apiVersion != Self.currentAPIVersion
        {
            throw PluginLoadError.unsupportedAPIVersion(pluginID: pluginInfo.id,
                                                        foundVersion: pluginInfo.apiVersion,
                                                        requiredVersion: Self.currentAPIVersion)
        }

        // Check for duplicate plugin ID
        if self.loadedPlugins[pluginInfo.id] != nil
        {
            self.logger.warning("Plugin '\(pluginInfo.id)' is already loaded, skipping")
            return
        }

        // Load principal class if specified (for lifecycle hooks)
        var principalClass: FabricPlugin.Type?
        
        if let principalClassName = pluginInfo.principalClassName
        {
            // For embedded plugins, we can reference the class directly since it's
            // compiled into the same module. This avoids Objective-C runtime issues.
            if pluginInfo.isEmbedded && pluginInfo.id == Self.coreNodesPluginID
            {
                principalClass = FabricCoreNodesPlugin.self
                self.logger.debug("Using embedded principal class: FabricCoreNodesPlugin")
            }
            else if let cls = NSClassFromString(principalClassName) as? FabricPlugin.Type
            {
                principalClass = cls
                self.logger.debug("Loaded principal class: \(principalClassName)")
            }
            else
            {
                throw PluginLoadError.principalClassLoadFailed(pluginID: pluginInfo.id, className: principalClassName)
            }
        }

        // Notify principal class that plugin did load
        principalClass?.pluginDidLoad(bundle: bundle)

        // Load node classes declared in Info.plist
        var loadedNodeClasses: [Node.Type] = []

        for className in pluginInfo.nodeClassNames
        {
            let nodeClass = try self.loadNodeClass(className: className, pluginID: pluginInfo.id)
            loadedNodeClasses.append(nodeClass)
        }

        // Get additional node classes from principal class
        if let additionalClasses = principalClass?.additionalNodeClasses()
        {
            for nodeClass in additionalClasses
            {
                loadedNodeClasses.append(nodeClass)
            }
        }

        // Register all node classes
        for nodeClass in loadedNodeClasses
        {
            try self.registerNodeClass(nodeClass, pluginID: pluginInfo.id)
        }

        // Store plugin info
        self.loadedPlugins[pluginInfo.id] = pluginInfo

        self.logger.info("Successfully loaded plugin '\(pluginInfo.displayName)' with \(loadedNodeClasses.count) node(s)")
    }

    // MARK: - Class Name Resolution

    /// Resolves a class name, checking aliases for backward compatibility.
    /// - Parameter className: The class name to resolve (may be legacy unqualified name)
    /// - Returns: The resolved class name
    public func resolveClassName(_ className: String) -> String
    {
        return self.classNameAliases[className] ?? className
    }

    /// Registers a legacy class name alias for backward compatibility.
    /// - Parameters:
    ///   - legacyName: The old class name (e.g., "PerspectiveCameraNode")
    ///   - currentName: The current qualified name (e.g., "Fabric.PerspectiveCameraNode")
    public func registerClassNameAlias(legacyName: String, currentName: String)
    {
        self.classNameAliases[legacyName] = currentName
    }

    // MARK: - Private Helpers

    /// Loads a node class by name from a plugin.
    /// - Parameters:
    ///   - className: Fully qualified class name (e.g., "MyPlugin.MyNode")
    ///   - pluginID: Bundle identifier of the plugin
    /// - Returns: The loaded Node.Type
    /// - Throws: PluginLoadError if class cannot be loaded
    private func loadNodeClass(className: String, pluginID: String) throws -> Node.Type
    {
        guard let cls = NSClassFromString(className)
        else
        {
            throw PluginLoadError.classNotFound(pluginID: pluginID, className: className)
        }

        guard let nodeClass = cls as? Node.Type
        else
        {
            throw PluginLoadError.classNotNodeSubclass(pluginID: pluginID, className: className)
        }

        return nodeClass
    }

    /// Registers a node class from a plugin.
    /// - Parameters:
    ///   - nodeClass: The Node.Type to register
    ///   - pluginID: Bundle identifier of the plugin providing this class
    /// - Throws: PluginLoadError if a node with the same name already exists
    private func registerNodeClass(_ nodeClass: Node.Type, pluginID: String) throws
    {
        let nodeName = String(describing: nodeClass)

        // Check for duplicates in already-loaded plugin nodes
        if let existing = self.pluginNodeClasses[nodeName]
        {
            throw PluginLoadError.duplicateNodeName(pluginID: pluginID,
                                                    nodeName: nodeName,
                                                    existingSource: "plugin '\(existing.pluginID)'")
        }

        // Register the node class
        self.pluginNodeClasses[nodeName] = (nodeClass: nodeClass, pluginID: pluginID)

        // Create wrapper for availableNodes
        let wrapper = NodeClassWrapper(nodeClass: nodeClass,
                                       nodeType: nodeClass.nodeType,
                                       fileURL: nil,
                                       nodeName: nodeClass.name,
                                       pluginBundleID: pluginID)
        
        self.pluginNodeWrappers.append(wrapper)

        // Register legacy alias (unqualified name -> qualified name)
        // This helps with backward compatibility for documents saved without module prefix
        let unqualifiedName = String(nodeName.split(separator: ".").last ?? Substring(nodeName))
        
        if unqualifiedName != nodeName
        {
            self.classNameAliases[unqualifiedName] = nodeName
        }

        self.logger.debug("Registered node class '\(nodeName)' from plugin '\(pluginID)'")
    }
}
