import Testing
import Foundation
import Metal
@testable import Fabric
import Satin
import simd

/// Two port declarations nothing enforces, swept across every node the
/// registry offers.
///
/// A node declares its ports by hand in `registerPorts`, and nothing stops it
/// declaring a plain `NodePort<Float>` where a `ParameterPort<Float>` belongs —
/// the graph still builds, connects and executes, the inlet just has no value
/// of its own to edit when nothing is wired to it. The declaration is then made
/// a second time, separately, by `SubgraphNode.makeProxy(for:)` when a port is
/// published: an inner port with no case there gets no proxy at all, and a
/// proxy presenting a different type — or losing the parameter — is a port the
/// parent graph cannot patch the way the sub graph could.
///
/// Parameter-backed means `parameter != nil` throughout, which is the same
/// thing `AnyPort` persists as `isParameterPort` and `Node.parameterGroup`
/// builds its UI from.
@Suite("Parameter Port Conformance")
struct ParameterPortConformanceTests
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

    /// Whether a port of this type could be parameter-backed, asked of the
    /// library rather than restated here: `DefaultParameterProviding` is what
    /// PassThroughNode consults to make the same decision, so the two cannot
    /// drift apart.
    private func canBeParameter(_ portType: PortType) -> Bool
    {
        portType.type is any DefaultParameterProviding.Type
    }

    private func label(_ wrapper: NodeClassWrapper) -> String
    {
        "\(wrapper.nodeName) (\(String(describing: wrapper.nodeClass)))"
    }

    /// Every node in the registry, instantiated once. A node that cannot be
    /// instantiated is skipped — the port round-trip contract suite owns that
    /// failure, and reporting it twice helps no one.
    private func eachRegisteredNode(context: Context, body: (NodeClassWrapper, Node) -> Void) throws
    {
        let wrappers = try NodeRegistry.shared.availableNodes
        #expect(!wrappers.isEmpty)

        for wrapper in wrappers
        {
            guard let node = try? wrapper.initializeNode(context: context) else { continue }

            body(wrapper, node)
        }
    }

    private func record(_ violations: [String], _ summary: String, sourceLocation: SourceLocation = #_sourceLocation)
    {
        guard !violations.isEmpty else { return }

        Issue.record(Comment(rawValue: "\(violations.count) \(summary):\n\(violations.joined(separator: "\n"))"),
                     sourceLocation: sourceLocation)
    }

    @Test("Every inlet whose type can be a parameter carries one", .timeLimit(.minutes(5)))
    func everyParameterCapableInletIsAParameterPort() throws
    {
        guard let context = makeContext() else { return }

        var violations: [String] = []
        var inletsChecked = 0

        try eachRegisteredNode(context: context)
        { wrapper, node in
            for port in node.ports where port.kind == .Inlet && canBeParameter(port.portType)
            {
                inletsChecked += 1

                guard port.parameter == nil else { continue }

                violations.append("\(label(wrapper)): \(port.name) [\(port.portType.rawValue)] is \(type(of: port)), expected a ParameterPort")
            }
        }

        #expect(inletsChecked > 0)
        record(violations, "inlet(s) that could be parameter-backed are not")
    }

    @Test("A sub graph's proxy ports present the ports they proxy", .timeLimit(.minutes(10)))
    func everyPublishedPortGetsAProxyThatMatchesIt() throws
    {
        guard let context = makeContext() else { return }

        var violations: [String] = []
        var portsChecked = 0

        try eachRegisteredNode(context: context)
        { wrapper, node in
            let subGraph = Graph(context: context)
            subGraph.addNode(node)

            let subgraphNode = SubgraphNode(context: context, subGraph: subGraph)

            // Publishing the whole node is the most a SubgraphNode can be asked
            // to proxy. Rebuilding the group is what tells it they changed.
            for port in node.ports
            {
                port.published = true
            }

            subGraph.rebuildPublishedParameterGroup()

            let proxiesByInnerPortID = Dictionary(
                subgraphNode.ports.compactMap { proxy -> (UUID, Fabric.Port)? in
                    guard let innerPortID = (proxy as? any ProxyPortProtocol)?.innerPortID else { return nil }
                    return (innerPortID, proxy)
                },
                uniquingKeysWith: { first, _ in first }
            )

            for port in node.ports
            {
                portsChecked += 1

                guard let proxy = proxiesByInnerPortID[port.id]
                else
                {
                    violations.append("\(label(wrapper)): \(port.name) [\(port.portType.rawValue)] published but not proxied — no case for \(type(of: port))")
                    continue
                }

                if proxy.kind != port.kind
                {
                    violations.append("\(label(wrapper)): \(port.name) proxied as \(proxy.kind), inner port is \(port.kind)")
                }

                if proxy.portType != port.portType
                {
                    violations.append("\(label(wrapper)): \(port.name) proxied as [\(proxy.portType.rawValue)], inner port is [\(port.portType.rawValue)]")
                }

                if (proxy.parameter == nil) != (port.parameter == nil)
                {
                    let proxied = proxy.parameter == nil ? "without a parameter" : "with a parameter"
                    let inner = port.parameter == nil ? "has none" : "has one"
                    violations.append("\(label(wrapper)): \(port.name) proxied \(proxied), inner port \(inner)")
                }
            }
        }

        #expect(portsChecked > 0)
        record(violations, "proxy port(s) do not present the port they proxy")
    }
}
