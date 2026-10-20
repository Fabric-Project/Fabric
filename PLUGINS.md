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

## Build Setup

A plugin links the `Fabric` package product but must not embed it: in the plugin target's *Frameworks and Libraries*, set `Fabric` to **Do Not Embed**. The host application already has `Fabric.framework` loaded, and the plugin binds to it at load time.

Xcode still copies the resource bundles of every package Fabric depends on (`Fabric_Fabric.bundle`, `Satin_Satin.bundle`, `mlx-swift_Cmlx.bundle`, …) into the plugin, and embeds Fabric's `Syphon.framework` and `HapInAVFoundation.framework`. The host ships all of these, and Fabric only ever loads the host's copies, so in the plugin they are about 20 MB of dead weight. Fabric provides `scripts/strip-fabric-plugin-payload.sh` to remove them.

1. Set **User Script Sandboxing** (`ENABLE_USER_SCRIPT_SANDBOXING`) to **No** for the plugin target, so the script can remove items from the built product.
2. Add a **Run Script** build phase as the last phase of the plugin target, with *Based on dependency analysis* unchecked:

   ```sh
   FABRIC_SOURCE_DIR="${FABRIC_SOURCE_DIR:-${BUILD_DIR%/Build/*}/SourcePackages/checkouts/Fabric}"
   "${FABRIC_SOURCE_DIR}/scripts/strip-fabric-plugin-payload.sh"
   ```

   This finds the copy of Fabric Xcode checked out for a package added by URL, in regular builds and archives alike.
3. If Fabric is added as a local package instead, add a user-defined `FABRIC_SOURCE_DIR` build setting to the plugin target pointing at your Fabric folder, for example `${PROJECT_DIR}/../Fabric`.

Xcode signs the bundle after the last build phase, so the signature covers the stripped bundle.

The script removes only the items it names, so the plugin's own resources, including resource bundles from the plugin's own package dependencies, are left alone. If a plugin needs to keep one of the named items, list it in a `FABRIC_PLUGIN_KEEP` build setting, separated by spaces, e.g. `mlx-swift_Cmlx.bundle`. It refuses any bundle that is not a `.fabricplugin`, since a host application needs everything it would remove.

The script can also be run on a built plugin by hand. A built plugin is already signed, and stripping it invalidates that signature, so re-sign it afterwards:

```sh
scripts/strip-fabric-plugin-payload.sh path/to/MyPlugin.fabricplugin
codesign --force --sign <identity> path/to/MyPlugin.fabricplugin
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

## Command Buffers

The command buffer handed to `execute` is always an `MPSCommandBuffer`: `GraphRenderer` and `GraphExportRenderer` wrap it once, where they create it, before any node sees it. Nodes may encode Metal Performance Shaders work on it, including `MPSGraphExecutable.encode(to:)`, which may call `commitAndContinue()`. Nodes must never wrap it in another `MPSCommandBuffer`, and never commit it: the renderer owns it and commits it once per frame.

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
