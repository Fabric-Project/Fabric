# Fabric Plugin Development Guide

This document describes how to create plugins for Fabric. Plugins allow you to extend Fabric with custom nodes that integrate seamlessly with the built-in node library.

## Overview

Fabric uses a plugin architecture inspired by Apple's QCPlugin system. Plugins are `.fabricplugin` bundles that contain:
- Compiled Swift/Objective-C code defining `Node` subclasses
- An `Info.plist` declaring plugin metadata and node classes
- Optional resources (shaders, assets, etc.)

**Important:** Fabric dogfoods its own plugin system. All built-in nodes are loaded through the same plugin API that third-party developers use, via the bundled `FabricCoreNodes.fabricplugin`.

## Plugin Bundle Structure

```
MyPlugin.fabricplugin/
  Contents/
    Info.plist           # Bundle metadata + node class list
    MacOS/
      MyPlugin           # Compiled Mach-O executable
    Resources/           # Optional shaders, assets
```

## Info.plist Schema

Your plugin's `Info.plist` must include these keys:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required: Bundle identifier -->
    <key>CFBundleIdentifier</key>
    <string>com.example.MyFabricPlugin</string>

    <!-- Required: Bundle name -->
    <key>CFBundleName</key>
    <string>MyPlugin</string>

    <!-- Required: API version (must be 1) -->
    <key>FabricPluginAPIVersion</key>
    <integer>1</integer>

    <!-- Required: List of node class names to register -->
    <key>FabricPluginNodeClasses</key>
    <array>
        <string>MyPlugin.MyCustomEffectNode</string>
        <string>MyPlugin.MyGeneratorNode</string>
    </array>

    <!-- Optional: Human-readable display name -->
    <key>FabricPluginDisplayName</key>
    <string>My Awesome Plugin</string>

    <!-- Optional: Author name -->
    <key>FabricPluginAuthor</key>
    <string>Developer Name</string>

    <!-- Optional: Plugin description -->
    <key>FabricPluginDescription</key>
    <string>Adds custom effects and generators</string>

    <!-- Optional: Version -->
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>

    <!-- Optional: Principal class for lifecycle hooks -->
    <key>NSPrincipalClass</key>
    <string>MyPlugin.PluginMain</string>
</dict>
</plist>
```

### Class Name Format

Node class names in `FabricPluginNodeClasses` must be fully qualified with the module name:
- `MyPlugin.MyCustomNode` (correct)
- `MyCustomNode` (incorrect - will not be found)

For generic types, use the mangled Swift name as returned by `String(describing: MyType.self)`.

## Creating a Node

Nodes are subclasses of `Fabric.Node`. Here's a complete example:

```swift
import Fabric
import Metal
import simd

public class MyCustomEffectNode: Node {

    // MARK: - Node Metadata (Required)

    override public class var name: String {
        "My Custom Effect"
    }

    override public class var nodeType: Node.NodeType {
        .Image(imageType: .ColorEffect)
    }

    override public class var nodeExecutionMode: Node.ExecutionMode {
        .Processor
    }

    override public class var nodeTimeMode: Node.TimeMode {
        .None
    }

    override public class var nodeDescription: String {
        "Applies a custom color effect to the input image"
    }

    // MARK: - Port Registration

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        return [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet,
                description: "The input image to process")),
            ("inputIntensity", ParameterPort(parameter: FloatParameter("Intensity", 1.0, 0.0...2.0, .slider,
                description: "Effect intensity"))),
            ("outputImage", NodePort<FabricImage>(name: "Image", kind: .Outlet,
                description: "The processed image")),
        ]
    }

    // MARK: - Port Accessors

    var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    var inputIntensity: ParameterPort<Float> { port(named: "inputIntensity") }
    var outputImage: NodePort<FabricImage> { port(named: "outputImage") }

    // MARK: - Execution

    override public func execute(
        context: GraphExecutionContext,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let image = inputImage.value else { return }

        let intensity = inputIntensity.value ?? 1.0

        // Process the image...
        // let processedImage = ...

        outputImage.send(processedImage)
    }
}
```

## Node Types

The `nodeType` class property determines where your node appears in the UI:

| Type | Description |
|------|-------------|
| `.Camera` | Camera nodes (perspective, orthographic) |
| `.Light` | Light sources (directional, point) |
| `.Object` | 3D objects and meshes |
| `.Geometery` | Geometry generators |
| `.Material` | Materials and shaders |
| `.Image(imageType:)` | Image processing nodes |
| `.Macro` | Subgraph and iterator nodes |
| `.Parameter` | Value generators and operators |
| `.IO` | Input/Output (MIDI, OSC, HID) |
| `.Utility` | Utility nodes |

### Image Types

For `.Image` nodes, specify the `imageType`:

| ImageType | Description |
|-----------|-------------|
| `.ColorEffect` | Single-input color effects |
| `.Generator` | Image generators (no input) |
| `.ShapeGenerator` | Shape/pattern generators |
| `.Transition` | Two-input transitions |
| `.Composite` | Compositing operations |
| `.Blur` | Blur effects |
| `.Distortion` | Distortion effects |
| `.Stylize` | Stylization effects |

## Execution Modes

The `nodeExecutionMode` determines when your node executes:

| Mode | Description |
|------|-------------|
| `.Provider` | Provides data (executes when dirty) |
| `.Processor` | Processes data (executes when inputs change) |
| `.Consumer` | Consumes data (renders, logs, outputs) |

## Plugin Lifecycle Hooks

For advanced use cases, implement the `FabricPlugin` protocol:

```swift
import Fabric

public class PluginMain: NSObject, FabricPlugin {

    public static func pluginDidLoad(bundle: Bundle) {
        // Called after the plugin bundle loads
        // Initialize resources, register additional nodes, etc.
    }

    public static func pluginWillUnload() {
        // Called before the plugin unloads
        // Clean up resources
    }

    public static func additionalNodeClasses() -> [Node.Type] {
        // Return additional node classes not listed in Info.plist
        // Useful for dynamically-generated nodes or conditional registration
        return [
            ConditionalNode.self,
        ]
    }
}
```

## Plugin Discovery Locations

Plugins are discovered in the following locations (in order):

1. **App-bundled plugins**: `Fabric.app/Contents/PlugIns/`
2. **User plugins**: `~/Library/Application Support/Fabric/Plugins/`
3. **System-wide plugins**: `/Library/Application Support/Fabric/Plugins/`

To install a plugin, simply copy the `.fabricplugin` bundle to one of these directories and restart Fabric.

## Accessing Framework Resources

Your plugin can access the Metal device and other framework resources through the `context`:

```swift
override public func execute(context: GraphExecutionContext, ...) {
    let device = self.context.device
    // Use device for Metal operations
}
```

## Error Handling

If your plugin fails to load, Fabric will log the error and continue. Common issues:

| Error | Cause |
|-------|-------|
| `bundleLoadFailed` | Bundle couldn't be loaded (missing executable, code signing issue) |
| `missingBundleIdentifier` | `CFBundleIdentifier` not set in Info.plist |
| `noNodeClassesDeclared` | `FabricPluginNodeClasses` is empty and no principal class |
| `unsupportedAPIVersion` | `FabricPluginAPIVersion` doesn't match current version (1) |
| `classNotFound` | Declared class name not found in bundle |
| `classNotNodeSubclass` | Class exists but doesn't inherit from `Node` |
| `duplicateNodeName` | Another plugin already registered a node with this name |

Check the Console.app for logs with category `info.HiRez.Fabric.PluginLoader`.

## Best Practices

1. **Use unique bundle identifiers**: `com.yourcompany.fabric.pluginname`
2. **Version your plugins**: Use semantic versioning in `CFBundleShortVersionString`
3. **Document your nodes**: Provide clear `nodeDescription` and port descriptions
4. **Handle missing inputs gracefully**: Check for nil values before processing
5. **Clean up resources**: Implement cleanup in `pluginWillUnload()` if needed
6. **Test on fresh installs**: Ensure your plugin works without development environment

## Building Plugins with SwiftPM

You can create a Swift Package that produces a plugin:

```swift
// Package.swift
import PackageDescription

let package = Package(
    name: "MyFabricPlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MyFabricPlugin", type: .dynamic, targets: ["MyFabricPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Fabric-Project/Fabric", branch: "main"),
    ],
    targets: [
        .target(
            name: "MyFabricPlugin",
            dependencies: [
                .product(name: "Fabric", package: "Fabric"),
            ]
        ),
    ]
)
```

After building, package the resulting `.dylib` as a `.fabricplugin` bundle.

## Example: Complete Plugin

See the `FabricCoreNodesPlugin` in the Fabric source code for a complete example of how the built-in nodes are registered. This is the reference implementation that demonstrates all plugin capabilities.

## API Version History

| Version | Fabric Version | Notes |
|---------|----------------|-------|
| 1 | Alpha | Initial plugin API |

## Getting Help

- File issues on [GitHub](https://github.com/Fabric-Project/Fabric/issues)
- Join the [Discord community](https://discord.gg/CrG92BG7xp)
- Check the [Architecture documentation](ARCHITECTURE.md) for understanding Fabric internals
