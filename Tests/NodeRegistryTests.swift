import Testing
import Foundation
import simd
@testable import Fabric

@Suite("Node Registry")
struct NodeRegistryTests {

    @Test("Core nodes are loaded through the plugin loader")
    func coreNodesLoadThroughPluginLoader() throws {
        let registry = try NodeRegistry()

        let nodeClassFound = registry.nodeClass(pluginID: PluginLoader.coreNodesPluginID,
                                                nodeID: "PerspectiveCameraNode") != nil
        #expect(nodeClassFound)
        #expect(PluginLoader.shared.loadedPlugins[FabricCoreNodesPlugin.pluginID] != nil)

        let perspectiveWrapper = registry.availableNodes.first { wrapper in
            wrapper.nodeClass == PerspectiveCameraNode.self
        }
        #expect(perspectiveWrapper?.pluginBundleID == FabricCoreNodesPlugin.pluginID)
    }

    @Test("Shader-backed dynamic nodes are owned by the core plugin")
    func dynamicShaderNodesLoadThroughCorePlugin() throws {
        let registry = try NodeRegistry()

        let dynamicNodes = registry.availableNodes.filter { wrapper in
            wrapper.fileURL?.pathExtension == "metal"
        }

        #expect(!dynamicNodes.isEmpty)
        #expect(dynamicNodes.allSatisfy { $0.pluginBundleID == FabricCoreNodesPlugin.pluginID })
    }

    // Plugin loading is lazy and mutates lookup dictionaries. Concurrent first
    // access from render queues must only allow one loader pass to initialize
    // the registry.
    @Test("Concurrent first access to a cold registry is safe")
    func nodeRegistryConcurrentFirstAccess() async throws {
        for _ in 0..<100 {
            // Fresh registry wrapper so each iteration hits the loader path.
            let registry = try NodeRegistry()
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<16 {
                    group.addTask {
                        _ = registry.nodeClass(pluginID: PluginLoader.coreNodesPluginID,
                                               nodeID: "PerspectiveCameraNode")
                    }
                }
            }
            // Compare as Bool: passing an Optional<Node.Type> through #expect's
            // generic __checkBinaryOperation crashes the runtime's metadata
            // instantiation (metatype generic argument), independent of the
            // registry race this test guards against.
            let found = registry.nodeClass(pluginID: PluginLoader.coreNodesPluginID,
                                           nodeID: "PerspectiveCameraNode") != nil
            #expect(found)
        }
    }

    // MARK: - Legacy aliases

    /// A saved graph spells a generic parameter the way `String(describing:)` prints
    /// it, which is the underlying type rather than the source alias. These are the
    /// spellings that actually appear in documents, so they are the ones the legacy
    /// lookup has to answer to — asserting them here keeps the table honest, since
    /// nothing else would notice an entry that can never match.
    @Test("Legacy array-node aliases resolve the spellings documents use")
    func legacyArrayAliasesUseDocumentSpellings() throws {
        let registry = try NodeRegistry()

        for nodeID in ["ArrayCountNode<SIMD3<Float>>",
                       "ArrayIndexValueNode<SIMD4<Float>>",
                       "ArrayQueueNode<SIMD2<Float>>",
                       "ArrayAppendNode<Float>",
                       "ArrayReplaceValueAtIndexNode<simd_float4x4>"] {
            let resolved = registry.nodeClass(pluginID: PluginLoader.coreNodesPluginID,
                                              nodeID: nodeID) != nil
            #expect(resolved, "no legacy alias for '\(nodeID)'")
        }
    }

    @Test("Legacy vector compose/decompose aliases resolve the spellings documents use")
    func legacyVectorAliasesUseDocumentSpellings() throws {
        let registry = try NodeRegistry()

        for nodeID in ["ComposeVectorNode<SIMD2<Float>>",
                       "DecomposeVectorNode<SIMD3<Float>>",
                       "ComposeVectorArrayNode<SIMD4<Float>>",
                       "DecomposeVectorArrayNode<SIMD3<Float>>"] {
            let resolved = registry.nodeClass(pluginID: PluginLoader.coreNodesPluginID,
                                              nodeID: nodeID) != nil
            #expect(resolved, "no legacy alias for '\(nodeID)'")
        }
    }

    /// The spelling that motivated the fix: `simd_float3` is a typealias, so it is
    /// never what a document contains. Guards against the table drifting back.
    @Test("Source-alias spellings are not what the lookup is keyed on")
    func legacyAliasesAreNotKeyedOnSourceSpellings() throws {
        let registry = try NodeRegistry()

        let sourceSpellingResolves = registry.nodeClass(pluginID: PluginLoader.coreNodesPluginID,
                                                        nodeID: "ArrayCountNode<simd_float3>") != nil
        #expect(!sourceSpellingResolves,
                "keyed on a spelling no document contains — the SIMD3<Float> form is the real one")
    }

    /// `String(describing:)` is the source of truth for both halves of the mapping,
    /// so pin the assumption the alias table rests on rather than trusting it.
    @Test("simd typealiases print as their underlying SIMD types")
    func simdTypeNamesPrintAsUnderlyingTypes() {
        #expect(String(describing: simd_float2.self) == "SIMD2<Float>")
        #expect(String(describing: simd_float3.self) == "SIMD3<Float>")
        #expect(String(describing: simd_float4.self) == "SIMD4<Float>")
        // Not a SIMD typealias — a struct, so it keeps its own name.
        #expect(String(describing: simd_float4x4.self) == "simd_float4x4")
    }
}
