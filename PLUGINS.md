# Fabric Plugin Development Guide

Fabric plugins provide `Node` subclasses through the same registration path used by Fabric's built-in nodes.

Fabric's core nodes are supplied by an embedded plugin implementation compiled into the Fabric framework. This keeps Swift Package integration zero-config: clients only depend on the `Fabric` product, and `NodeRegistry` transparently loads the embedded core plugin before any external bundles.

External plugins are `.fabricplugin` bundles loaded after the embedded core plugin.

## Bundle Layout

```text
MyPlugin.fabricplugin/
  Contents/
    Info.plist
    MacOS/
      MyPlugin
    Resources/
```

## Info.plist Keys

Required:

- `CFBundleIdentifier`: unique plugin identifier.
- `CFBundleName`: bundle name.
- `FabricPluginAPIVersion`: integer API version. Current value is `1`.
- `FabricPluginNodeClasses`: fully qualified Swift node class names, or provide `NSPrincipalClass` with `FabricPlugin.additionalNodeClasses()`.

Optional:

- `FabricPluginDisplayName`
- `FabricPluginAuthor`
- `FabricPluginDescription`
- `CFBundleShortVersionString`
- `NSPrincipalClass`

Example:

```xml
<key>FabricPluginAPIVersion</key>
<integer>1</integer>
<key>FabricPluginNodeClasses</key>
<array>
    <string>MyPlugin.MyCustomNode</string>
</array>
```

## Lifecycle

Plugins may define a principal class:

```swift
import Fabric

public final class PluginMain: NSObject, FabricPlugin
{
    public static func pluginDidLoad(bundle: Bundle) {}
    public static func pluginWillUnload() {}
    public static func additionalNodeClasses() -> [Node.Type] { [] }
}
```

## Discovery

`NodeRegistry` transparently asks `PluginLoader` to load plugins on first use. The embedded core plugin is always loaded first.

Fabric searches, in this order:

- `Fabric.app/Contents/PlugIns/`
- `~/Library/Application Support/Fabric/Plugins/`
- `/Library/Application Support/Fabric/Plugins/` on macOS

## Precedence

**Search order is precedence.** The first bundle found to declare a given plugin identifier wins; later bundles declaring the same identifier are ignored, logged, and *not* treated as errors.

This is what lets an application embed a plugin in its own `Contents/PlugIns/` *and* install a copy in the user's plugin folder for other Fabric hosts to share. Inside that application the embedded copy wins; every other host loads the installed one. Both apps work, and neither has to know what the other did.

## Loading Errors

Plugin loading is non-fatal. One bundle's failure costs that bundle only — Fabric records the error in `NodeRegistry.pluginLoadErrors` for a host to surface, and continues with the remaining bundles. This matters in a shared plugin folder: a stale or malformed bundle must not take down the plugins behind it in the search order, including the host's own.

Errors are represented for missing bundles, bundle load failures, missing identifiers, unsupported API versions, missing node declarations, missing classes, non-node classes, principal-class failures, and duplicate node names.

A plugin whose node names collide with already-registered ones is rejected as a whole, so a bundle cannot partially register.

The embedded core plugin is fatal to useful operation if it fails to register, but the failure is still represented in `NodeRegistry.pluginLoadErrors` so callers can surface it in UI.
