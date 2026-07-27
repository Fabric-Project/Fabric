import Testing
import Foundation
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
}
