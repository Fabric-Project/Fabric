import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// A node's port set and order are a function of what it declares from: equal
/// settings give equal ports, in equal order, however the node got there.
@Suite("Declared Ports Invariant")
@MainActor
struct DeclaredPortsInvariantTests
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

    private func shape(of node: Node) -> [String]
    {
        node.ports.map { "\($0.key):\($0.portType.rawValue):\($0.kind):\($0.control.map { "\($0)" } ?? "-")" }
    }

    private func roundTrip(_ node: Node, context: Context) throws -> Node
    {
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        return try decoder.decode(type(of: node), from: JSONEncoder().encode(node))
    }

    /// A node of `nodeClass` opened from a document holding `strategy` and no
    /// port state.
    private func freshNode(of nodeClass: StrategyNode.Type, strategy: String, context: Context) throws -> Node
    {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(nodeClass.init(context: context))) as? [String: Any])
        json["strategy"] = strategy
        json["ports"] = []
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        return try decoder.decode(nodeClass, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test("Every core node decodes with the ports it was saved with, in the same order")
    func everyNodeRoundTripsItsShape() throws
    {
        guard let context = makeContext() else { return }
        var failures: [String] = []

        for wrapper in try NodeRegistry.shared.availableNodes
        {
            guard let node = try? wrapper.initializeNode(context: context) else { continue }
            let decoded = try roundTrip(node, context: context)
            if shape(of: decoded) != shape(of: node)
            {
                failures.append("\(wrapper.nodeClass.name): \(shape(of: node)) decoded as \(shape(of: decoded))")
            }
        }

        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test("Every strategy node stands, after any run of strategy changes, as one made with its last strategy")
    func everyStrategyNodeFollowsItsStrategy() throws
    {
        guard let context = makeContext() else { return }
        var failures: [String] = []

        for wrapper in try NodeRegistry.shared.availableNodes
        {
            guard let node = try? wrapper.initializeNode(context: context) as? StrategyNode else { continue }
            let strategyClass = type(of: node)
            let strategies = strategyClass.strategies
            guard strategies.count > 1 else { continue }

            // Every strategy, then back to the first, then the last again.
            for strategy in strategies + [strategies[0], strategies[strategies.count - 1]]
            {
                node.strategy = strategy
                let fresh = try freshNode(of: strategyClass, strategy: strategy, context: context)
                if shape(of: node) != shape(of: fresh)
                {
                    failures.append("\(wrapper.nodeClass.name) at \(strategy): \(shape(of: node)) but fresh \(shape(of: fresh))")
                    break
                }
            }
        }

        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }
}
