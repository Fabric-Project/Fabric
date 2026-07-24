//
//  FabricPlugin.swift
//  Fabric
//
//  Created by Anton Marini on 7/24/26.
//

import Foundation

/// Optional lifecycle hooks for Fabric plugin bundles.
///
/// A plugin bundle can expose a principal class conforming to this protocol via
/// `NSPrincipalClass` in its Info.plist. Node classes can also be declared
/// directly in `FabricPluginNodeClasses`.
public protocol FabricPlugin: AnyObject
{
    /// Called after Fabric successfully loads the plugin bundle.
    static func pluginDidLoad(bundle: Bundle)

    /// Called before Fabric unloads the plugin bundle.
    static func pluginWillUnload()

    /// Additional node classes provided by this plugin.
    ///
    /// This supports plugins that build their node list at runtime instead of
    /// declaring every class in Info.plist.
    static func additionalNodeClasses() -> [Node.Type]
}

public extension FabricPlugin
{
    static func pluginDidLoad(bundle: Bundle) {}
    static func pluginWillUnload() {}
    static func additionalNodeClasses() -> [Node.Type] { [] }
}
