import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// The registry's list of subgraph nodes, which Embed Selection In offers:
/// the core kinds and any a plugin adds, fixed between plugin loads.
@Suite("Subgraph Nodes")
struct SubgraphNodesTests
{
    private func makeContext() -> Context?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(device: device,
                       sampleCount: 1,
                       colorPixelFormat: .bgra8Unorm,
                       depthPixelFormat: .depth32Float,
                       stencilPixelFormat: .invalid)
    }

    @Test("The registry lists every SubgraphNode subclass it holds, and nothing else")
    func registryListsSubgraphTypes() throws
    {
        let registry = try NodeRegistry.shared
        let subgraphNodes = registry.subgraphNodes

        let classNames = subgraphNodes.compactMap(\.subgraphClass).map { String(describing: $0) }
        #expect(classNames.contains("SubgraphNode"))
        #expect(classNames.contains("DeferredSubgraphNode"))
        #expect(classNames.contains("IteratorNode"))
        #expect(classNames.contains("EnvironmentNode"))

        let expectedCount = registry.availableNodes.filter { $0.nodeClass is SubgraphNode.Type }.count
        #expect(subgraphNodes.count == expectedCount)
        #expect(registry.availableNodes.map(\.id) == PluginLoader.shared.pluginNodeWrappers.map(\.id))
    }

    @Test("A selection can be embedded in every registered subgraph type")
    func everySubgraphTypeEmbeds() throws
    {
        guard let context = makeContext() else { return }
        let registry = try NodeRegistry.shared

        for subgraphNode in registry.subgraphNodes
        {
            let subgraphClass = try #require(subgraphNode.subgraphClass)
            let graph = Graph(context: context)
            let node = NumberBinaryOperator(context: context)
            graph.addNode(node)

            let container = try graph.createSubgraph(from: [node], centeredOn: node, usingClass: subgraphClass)

            #expect(Swift.type(of: container) == subgraphClass, "\(subgraphNode.nodeName)")
            #expect(container.subGraph.nodes.contains { $0 === node }, "\(subgraphNode.nodeName)")
        }
    }
}
