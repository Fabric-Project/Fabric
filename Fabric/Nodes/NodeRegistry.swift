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
    private static let sharedResult = Result { try NodeRegistry() }

    private let pluginLoadLock = NSRecursiveLock()

    public static var shared: NodeRegistry
    {
        get throws
        {
            try sharedResult.get()
        }
    }

    init() throws
    {
        try loadPluginsIfNeeded()
    }

    public func nodeClass(pluginID: String, nodeID: String) -> (Node.Type)?
    {
        if let legacyClass = self.legacyNodeClassLookup[PluginQualifiedNodeID(pluginID: pluginID, nodeID: nodeID)]
        {
            return legacyClass
        }

        return PluginLoader.shared.nodeClass(pluginID: pluginID, nodeID: nodeID)
    }

    /// Returns the first drop-target node class whose `supportedContentTypes`
    /// conforms to the given UTType. More specific types (e.g. .jpeg) are
    /// checked via `UTType.conforms(to:)`, so dropping a JPEG will match
    /// `ImageProviderNode` whose list includes `.image`.
    public func dropTargetNodeClass(for contentType: UTType) -> (any NodeFileLoadingProtocol.Type)?
    {
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
        return self.nodeFileLoadingClasses.flatMap { $0.supportedContentTypes }
    }()

    public lazy private(set) var availableNodes: [NodeClassWrapper] = {
        return PluginLoader.shared.pluginNodeWrappers
    }()

    public var pluginLoadErrors: [PluginLoadError]
    {
        return PluginLoader.shared.loadErrors
    }

    private var nodeFileLoadingClasses: [(any NodeFileLoadingProtocol.Type)]
    {
        PluginLoader.shared.pluginNodeClasses.values.compactMap { nodeClass in
            nodeClass as? any NodeFileLoadingProtocol.Type
        }
    }

    public func qualifiedNodeID(for nodeClass: Node.Type) -> PluginQualifiedNodeID?
    {
        PluginLoader.shared.qualifiedNodeID(for: nodeClass)
    }

    public func validatePluginRequirements(_ requirements: [PluginRequirement]) throws
    {
        for requirement in requirements
        {
            guard let pluginInfo = PluginLoader.shared.loadedPlugins[requirement.id] else
            {
                throw FabricError(.loading(.pluginNotFound),
                                  severity: .fatal,
                                  message: "Required plugin '\(requirement.id)' is not loaded")
            }

            guard Self.version(pluginInfo.version, isAtLeast: requirement.version) else
            {
                throw FabricError(.loading(.pluginLoadFailed),
                                  severity: .fatal,
                                  message: "Required plugin '\(requirement.id)' needs version \(requirement.version ?? ""), but loaded version is \(pluginInfo.version ?? "unknown")")
            }
        }
    }

    private lazy var legacyNodeClassLookup: [PluginQualifiedNodeID: Node.Type] = {
        var result: [PluginQualifiedNodeID: Node.Type] = [:]

        func registerCoreAlias(_ nodeID: String, _ nodeClass: Node.Type)
        {
            result[PluginQualifiedNodeID(pluginID: PluginLoader.coreNodesPluginID, nodeID: nodeID)] = nodeClass
        }

        // Legacy class-name aliases: old saved graphs used SatinGeometry in generic type params.
        // Both module-qualified and bare forms are covered since Swift's output can vary.
        registerCoreAlias("PassThroughNode<SatinGeometry>", PassThroughNode<Geometry>.self)
        registerCoreAlias("PassThroughNode<Satin.SatinGeometry>", PassThroughNode<Geometry>.self)

        // Structural array nodes were previously generic; old docs decode to type-agnostic versions.
        //
        // These suffixes must be spelled the way a *document* spells them, which is
        // `String(describing:)` of the generic parameter — and that prints the
        // underlying type, not the source alias. `simd_float2/3/4` are typealiases
        // for `SIMD2/3/4<Float>`, so a saved graph reads `ArrayCountNode<SIMD3<Float>>`
        // and never `ArrayCountNode<simd_float3>`. `simd_float4x4` is a struct in its
        // own right, so it is spelled as written.
        let agnosticSuffixes = [
            "Bool",
            "Int",
            "Float",
            "String",
            "SIMD2<Float>",
            "SIMD3<Float>",
            "SIMD4<Float>",
            "simd_float4x4",
            "FabricImage",
        ]

        for suffix in agnosticSuffixes
        {
            registerCoreAlias("ArrayQueueNode<\(suffix)>", ArrayQueueNode.self)
            registerCoreAlias("ArrayFirstValueNode<\(suffix)>", ArrayFirstValueNode.self)
            registerCoreAlias("ArrayLastValueNode<\(suffix)>", ArrayLastValueNode.self)
            registerCoreAlias("ArrayIndexValueNode<\(suffix)>", ArrayIndexValueNode.self)
            registerCoreAlias("ArrayCountNode<\(suffix)>", ArrayCountNode.self)
            registerCoreAlias("ArrayAppendNode<\(suffix)>", ArrayAppendNode.self)
            registerCoreAlias("ArrayReplaceValueAtIndexNode<\(suffix)>", ArrayReplaceValueAtIndexNode.self)
            registerCoreAlias("ArraySplitAtIndexNode<\(suffix)>", ArraySplitAtIndexNode.self)
        }

        // Vector compose/decompose nodes were previously generic; old docs map to consolidated versions.
        let vectorSuffixes = ["SIMD2<Float>", "SIMD3<Float>", "SIMD4<Float>"]

        for suffix in vectorSuffixes
        {
            registerCoreAlias("ComposeVectorNode<\(suffix)>", ComposeVectorNode.self)
            registerCoreAlias("DecomposeVectorNode<\(suffix)>", DecomposeVectorNode.self)
            registerCoreAlias("ComposeVectorArrayNode<\(suffix)>", ComposeVectorArrayNode.self)
            registerCoreAlias("DecomposeVectorArrayNode<\(suffix)>", DecomposeVectorArrayNode.self)
        }

        return result
    }()

    private static func version(_ loadedVersion: String?, isAtLeast requiredVersion: String?) -> Bool
    {
        guard let requiredVersion else { return true }
        guard let loadedVersion else { return false }

        let loadedComponents = loadedVersion.split(separator: ".").map { Int(String($0)) ?? 0 }
        let requiredComponents = requiredVersion.split(separator: ".").map { Int(String($0)) ?? 0 }
        let count = max(loadedComponents.count, requiredComponents.count)

        for index in 0..<count
        {
            let loaded = index < loadedComponents.count ? loadedComponents[index] : 0
            let required = index < requiredComponents.count ? requiredComponents[index] : 0

            if loaded > required { return true }
            if loaded < required { return false }
        }

        return true
    }

    private func loadPluginsIfNeeded() throws
    {
        pluginLoadLock.lock()
        defer { pluginLoadLock.unlock() }

        try PluginLoader.shared.loadAllPlugins()
    }
}
