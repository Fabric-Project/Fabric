import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// The decode contract behind declare-then-hydrate: the code, not the document,
/// owns the port set — so every node must recreate all of its ports during
/// init(from:), dynamic ones included, or the document's port state and wires
/// are silently dropped. That obligation is per-node and invisible at compile
/// time; this sweep enforces it for every node flavor the registry offers, by
/// round-tripping each through the real document path (Graph encode → decode →
/// encode) and comparing the persisted port sets.
@Suite("Node Port Round-Trip Contract")
struct NodePortRoundTripContractTests
{
    /// A port as the document sees it: registry key, identity, direction and
    /// wire type. Name-keyed state (values, published flags) is covered by the
    /// Port Hydration suite; this contract is about ports surviving at all.
    private struct PortFingerprint: Equatable, CustomStringConvertible
    {
        let registryKey: String
        let portID: String
        let kind: String
        let portType: String

        var description: String { "\(registryKey) [\(kind) \(portType)] \(portID)" }
    }

    private struct EncodedNode
    {
        let nodeID: String
        let typeName: String
        let ports: [PortFingerprint]
    }

    private func encodedNodes(from graphData: Data) throws -> [String: EncodedNode]
    {
        let object = try #require(try JSONSerialization.jsonObject(with: graphData) as? [String: Any])
        let nodeMap = try #require(object["nodeMap"] as? [[String: Any]])

        var result: [String: EncodedNode] = [:]

        for entry in nodeMap
        {
            let typeName = try #require(entry["type"] as? String)
            let value = try #require(entry["value"] as? [String: Any])
            let nodeID = try #require(value["id"] as? String)
            let ports = value["ports"] as? [[String: Any]] ?? []

            let fingerprints = try ports.map { snapshot -> PortFingerprint in
                let key = try #require(snapshot["name"] as? String)
                let payload = try #require(snapshot["payload"] as? [String: Any])
                let base = try #require(payload["base"] as? [String: Any])
                let portID = try #require(base["id"] as? String)
                let kind = try #require(base["kind"] as? String)
                let portType = String(describing: payload["type"] ?? "?")

                return PortFingerprint(registryKey: key, portID: portID, kind: kind, portType: portType)
            }

            result[nodeID] = EncodedNode(nodeID: nodeID, typeName: typeName, ports: fingerprints)
        }

        return result
    }

    @Test("Every registered node flavor survives encode → decode → encode with its port set intact",
          .timeLimit(.minutes(10)))
    func everyRegisteredNodeFlavorRoundTripsItsPorts() throws
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let context = Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )

        let wrappers = try NodeRegistry.shared.availableNodes
        #expect(!wrappers.isEmpty)

        for wrapper in wrappers
        {
            let label = "\(wrapper.nodeName) (\(String(describing: wrapper.nodeClass)))"

            let node: Node
            do
            {
                node = try wrapper.initializeNode(context: context)
            }
            catch
            {
                Issue.record("\(label): failed to instantiate — \(error)")
                continue
            }

            do
            {
                let graph = Graph(context: context)
                graph.addNode(node)

                let savedData = try JSONEncoder().encode(graph)
                let saved = try #require(try encodedNodes(from: savedData)[node.id.uuidString],
                                         "\(label): node missing from its own encoded graph")

                let decoder = JSONDecoder()
                decoder.context = DecoderContext(documentContext: context)
                let decodedGraph = try decoder.decode(Graph.self, from: savedData)

                let decodedNode = try #require(decodedGraph.nodes.first { $0.id == node.id },
                                               "\(label): node missing after decode")

                #expect(decodedNode.droppedPortStateKeys.isEmpty,
                        "\(label): decode dropped port state for keys \(decodedNode.droppedPortStateKeys)")

                let reencodedData = try JSONEncoder().encode(decodedGraph)
                let reencoded = try #require(try encodedNodes(from: reencodedData)[node.id.uuidString],
                                             "\(label): node missing from re-encoded graph")

                if saved.ports != reencoded.ports
                {
                    let savedKeys = saved.ports.map(\.registryKey)
                    let reencodedKeys = reencoded.ports.map(\.registryKey)
                    let lost = savedKeys.filter { !reencodedKeys.contains($0) }
                    let gained = reencodedKeys.filter { !savedKeys.contains($0) }

                    Issue.record("""
                        \(label): port set changed across round trip.
                        saved:      \(saved.ports)
                        re-encoded: \(reencoded.ports)
                        lost keys: \(lost) gained keys: \(gained)
                        """)
                }
            }
            catch
            {
                Issue.record("\(label): round trip threw — \(error)")
            }
        }
    }
}
