//
//  NodeRegistry.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//

import Foundation
import Satin
import UniformTypeIdentifiers

public class NodeRegistry
{
    public static let shared = NodeRegistry()

    private let pluginLoadLock = NSRecursiveLock()

    init() {}

    public func nodeClass(for nodeName: String) -> (Node.Type)?
    {
        self.loadPluginsIfNeeded()

        if let legacyClass = self.legacyNodeClassLookup[nodeName]
        {
            return legacyClass
        }

        return PluginLoader.shared.nodeClass(for: nodeName)
    }

    /// Returns the first drop-target node class whose `supportedContentTypes`
    /// conforms to the given UTType. More specific types (e.g. .jpeg) are
    /// checked via `UTType.conforms(to:)`, so dropping a JPEG will match
    /// `ImageProviderNode` whose list includes `.image`.
    public func dropTargetNodeClass(for contentType: UTType) -> (any NodeFileLoadingProtocol.Type)?
    {
        self.loadPluginsIfNeeded()

        for dropNodeClass in self.nodeFileLoadingClasses
        {
            if dropNodeClass.supportedContentTypes.contains(where: { contentType.conforms(to: $0) })
            {
                return dropNodeClass
            }
        }

        return nil
    }

    /// All UTTypes accepted by drop-target nodes, for use with drop destination handlers.
    public lazy private(set) var allSupportedDropTypes: [UTType] = {
        self.loadPluginsIfNeeded()
        return self.nodeFileLoadingClasses.flatMap { $0.supportedContentTypes }
    }()

    public lazy private(set) var availableNodes: [NodeClassWrapper] = {
        self.loadPluginsIfNeeded()
        return PluginLoader.shared.pluginNodeWrappers
    }()

    public var pluginLoadErrors: [PluginLoadError]
    {
        self.loadPluginsIfNeeded()
        return PluginLoader.shared.loadErrors
    }

    private var nodeFileLoadingClasses: [(any NodeFileLoadingProtocol.Type)]
    {
        PluginLoader.shared.pluginNodeClasses.values.compactMap { entry in
            entry.nodeClass as? any NodeFileLoadingProtocol.Type
        }
    }

    private lazy var legacyNodeClassLookup: [String: Node.Type] = {
        var result: [String: Node.Type] = [:]

        // Legacy class-name aliases: old saved graphs used SatinGeometry in generic type params.
        // Both module-qualified and bare forms are covered since Swift's output can vary.
        result["PassThroughNode<SatinGeometry>"] = PassThroughNode<Geometry>.self
        result["PassThroughNode<Satin.SatinGeometry>"] = PassThroughNode<Geometry>.self

        // Structural array nodes were previously generic; old docs decode to type-agnostic versions.
        let agnosticSuffixes = [
            "Bool",
            "Int",
            "Float",
            "String",
            "simd_float2",
            "simd_float3",
            "simd_float4",
            "simd_float4x4",
            "FabricImage",
        ]

        for suffix in agnosticSuffixes
        {
            result["ArrayQueueNode<\(suffix)>"] = ArrayQueueNode.self
            result["ArrayFirstValueNode<\(suffix)>"] = ArrayFirstValueNode.self
            result["ArrayLastValueNode<\(suffix)>"] = ArrayLastValueNode.self
            result["ArrayIndexValueNode<\(suffix)>"] = ArrayIndexValueNode.self
            result["ArrayCountNode<\(suffix)>"] = ArrayCountNode.self
            result["ArrayAppendNode<\(suffix)>"] = ArrayAppendNode.self
            result["ArrayReplaceValueAtIndexNode<\(suffix)>"] = ArrayReplaceValueAtIndexNode.self
            result["ArraySplitAtIndexNode<\(suffix)>"] = ArraySplitAtIndexNode.self
        }

        // Vector compose/decompose nodes were previously generic; old docs map to consolidated versions.
        let vectorSuffixes = ["simd_float2", "simd_float3", "simd_float4"]

        for suffix in vectorSuffixes
        {
            result["ComposeVectorNode<\(suffix)>"] = ComposeVectorNode.self
            result["DecomposeVectorNode<\(suffix)>"] = DecomposeVectorNode.self
            result["ComposeVectorArrayNode<\(suffix)>"] = ComposeVectorArrayNode.self
            result["DecomposeVectorArrayNode<\(suffix)>"] = DecomposeVectorArrayNode.self
        }

        return result
    }()

    private func loadPluginsIfNeeded()
    {
        pluginLoadLock.lock()
        defer { pluginLoadLock.unlock() }

        PluginLoader.shared.loadAllPlugins()
    }
}
