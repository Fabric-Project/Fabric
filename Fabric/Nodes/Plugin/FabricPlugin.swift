//
//  FabricPlugin.swift
//  Fabric
//
//  Created by Claude on 2/6/26.
//

import Foundation

/// Protocol for optional plugin lifecycle hooks.
/// Plugins can implement this protocol on their principal class to receive
/// lifecycle callbacks and provide additional node classes dynamically.
public protocol FabricPlugin: AnyObject {
    /// Called after the plugin bundle has been loaded.
    /// Use this to perform any necessary initialization.
    /// - Parameter bundle: The plugin's bundle
    static func pluginDidLoad(bundle: Bundle)

    /// Called before the plugin will be unloaded.
    /// Use this to perform any necessary cleanup.
    static func pluginWillUnload()

    /// Returns additional node classes that should be registered.
    /// This allows plugins to provide node classes dynamically beyond
    /// those declared in Info.plist's FabricPluginNodeClasses array.
    /// - Returns: Array of Node subclass types to register
    static func additionalNodeClasses() -> [Node.Type]
}

/// Default implementations for FabricPlugin protocol methods.
/// All methods are optional - plugins only need to implement what they need.
public extension FabricPlugin {
    static func pluginDidLoad(bundle: Bundle) {}
    static func pluginWillUnload() {}
    static func additionalNodeClasses() -> [Node.Type] { [] }
}
