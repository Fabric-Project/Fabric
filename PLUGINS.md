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

Fabric searches:

- `Fabric.app/Contents/PlugIns/`
- `~/Library/Application Support/Fabric/Plugins/`
- `/Library/Application Support/Fabric/Plugins/` on macOS

## Loading Errors

Plugin loading is non-fatal. Fabric logs errors and continues with other plugins. Phase 2 supports errors for missing bundles, bundle load failures, missing identifiers, unsupported API versions, missing node declarations, missing classes, non-node classes, principal-class failures, duplicate plugin identifiers, and duplicate node names.

The embedded core plugin is fatal to useful operation if it fails to register, but the failure is still represented in `NodeRegistry.pluginLoadErrors` so callers can surface it in UI.
