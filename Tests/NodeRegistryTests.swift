import Testing
import Foundation
@testable import Fabric

@Suite("Node Registry")
struct NodeRegistryTests {

    @Test("Core nodes are loaded through the plugin loader")
    func coreNodesLoadThroughPluginLoader() {
        let registry = NodeRegistry()

        let nodeClassFound = registry.nodeClass(for: "PerspectiveCameraNode") != nil
        #expect(nodeClassFound)
        #expect(PluginLoader.shared.loadedPlugins[FabricCoreNodesPlugin.pluginID] != nil)

        let perspectiveWrapper = registry.availableNodes.first { wrapper in
            wrapper.nodeClass == PerspectiveCameraNode.self
        }
        #expect(perspectiveWrapper?.pluginBundleID == FabricCoreNodesPlugin.pluginID)
    }

    @Test("Shader-backed dynamic nodes are owned by the core plugin")
    func dynamicShaderNodesLoadThroughCorePlugin() {
        let registry = NodeRegistry()

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
    func nodeRegistryConcurrentFirstAccess() async {
        for _ in 0..<100 {
            // Fresh registry wrapper so each iteration hits the loader path.
            let registry = NodeRegistry()
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<16 {
                    group.addTask {
                        _ = registry.nodeClass(for: "PerspectiveCameraNode")
                    }
                }
            }
            // Compare as Bool: passing an Optional<Node.Type> through #expect's
            // generic __checkBinaryOperation crashes the runtime's metadata
            // instantiation (metatype generic argument), independent of the
            // registry race this test guards against.
            let found = registry.nodeClass(for: "PerspectiveCameraNode") != nil
            #expect(found)
        }
    }
}
