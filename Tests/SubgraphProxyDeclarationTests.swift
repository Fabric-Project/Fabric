import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// A node whose one inlet is a Float or a Bool, as a setting would choose.
private final class SwitchingTypeNode: Node
{
    override class var name: String { "Switching Type" }
    override class var nodeType: Node.NodeType { .Utility }

    var carriesBool = false { didSet { reconcilePorts() } }

    override func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [PortDeclaration(key: "value", portType: carriesBool ? .Bool : .Float, kind: .Inlet, name: "Value")]
    }
}

/// A subgraph node's proxies are declarations from what its sub graph
/// publishes, reconciled as the sub graph's publishing changes.
@Suite("Subgraph proxy declarations", .serialized)
struct SubgraphProxyDeclarationTests
{
    private struct Fixture
    {
        let outer: Graph
        let subgraph: SubgraphNode
        let inner: NumberBinaryOperator
        let upstream: NumberBinaryOperator
        let undoManager: UndoManager

        var proxies: [Fabric.Port] { subgraph.ports.filter { $0 is any ProxyPortProtocol } }
    }

    private func makeFixture() throws -> Fixture
    {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let outer = Graph(context: context)
        let subgraph = SubgraphNode(context: context)
        let inner = NumberBinaryOperator(context: context)
        let upstream = NumberBinaryOperator(context: context)
        outer.addNode(subgraph)
        outer.addNode(upstream)
        subgraph.subGraph.addNode(inner)
        subgraph.subGraph.setPublished(true, port: inner.inputNumber1)

        let proxy = try #require(subgraph.ports.first { $0 is any ProxyPortProtocol })
        try #require(outer.connect(upstream.outputNumber, to: proxy) != nil)

        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        outer.undoManager = undoManager
        subgraph.subGraph.undoManager = undoManager
        return Fixture(outer: outer, subgraph: subgraph, inner: inner, upstream: upstream, undoManager: undoManager)
    }

    private func expectWired(_ fixture: Fixture, sourceLocation: SourceLocation = #_sourceLocation) throws
    {
        let proxy = try #require(fixture.proxies.first, sourceLocation: sourceLocation)
        #expect(fixture.proxies.count == 1, sourceLocation: sourceLocation)
        #expect(proxy.key == PortKey.proxy(node: fixture.inner.id, inner: .own("inputNumber1")), sourceLocation: sourceLocation)
        #expect((proxy as? any ProxyPortProtocol)?.wraps(fixture.inner.inputNumber1) == true, sourceLocation: sourceLocation)
        #expect(fixture.outer.connections.count == 1, sourceLocation: sourceLocation)
        #expect(fixture.outer.connections.first?.inletPort === proxy, sourceLocation: sourceLocation)
        #expect(proxy.connections.count == 1, sourceLocation: sourceLocation)
    }

    private func expectUnwired(_ fixture: Fixture, sourceLocation: SourceLocation = #_sourceLocation)
    {
        #expect(fixture.proxies.isEmpty, sourceLocation: sourceLocation)
        #expect(fixture.outer.connections.isEmpty, sourceLocation: sourceLocation)
        #expect(fixture.upstream.outputNumber.connections.isEmpty, sourceLocation: sourceLocation)
    }

    private func step(_ fixture: Fixture, _ edit: () -> Void)
    {
        fixture.undoManager.beginUndoGrouping()
        edit()
        fixture.undoManager.endUndoGrouping()
    }

    @Test("Unpublishing inside takes the proxy and its wires; undo brings both back, wire after proxy")
    func unpublishUndoRestoresWires() throws
    {
        let fixture = try makeFixture()
        try expectWired(fixture)

        step(fixture) { fixture.subgraph.subGraph.setPublished(false, port: fixture.inner.inputNumber1) }
        expectUnwired(fixture)

        fixture.undoManager.undo()
        try expectWired(fixture)
        fixture.undoManager.redo()
        expectUnwired(fixture)
        fixture.undoManager.undo()
        try expectWired(fixture)
    }

    @Test("Deleting a published inner node takes the proxy and its wires; undo brings both back")
    func deleteUndoRestoresWires() throws
    {
        let fixture = try makeFixture()

        step(fixture) { fixture.subgraph.subGraph.delete(node: fixture.inner) }
        expectUnwired(fixture)

        fixture.undoManager.undo()
        try expectWired(fixture)
        fixture.undoManager.redo()
        expectUnwired(fixture)
        fixture.undoManager.undo()
        try expectWired(fixture)
    }

    @Test("An inner port retyped under its key retypes the proxy at the same address, keeping its publishing")
    func retypedInnerPortRetypesProxy() throws
    {
        let fixture = try makeFixture()
        fixture.outer.undoManager = nil
        fixture.subgraph.subGraph.undoManager = nil
        let switching = SwitchingTypeNode(context: fixture.inner.context)
        fixture.subgraph.subGraph.addNode(switching)
        let innerPort = try #require(switching.port(forKey: .own("value")))
        fixture.subgraph.subGraph.setPublished(true, port: innerPort)
        let proxy = try #require(fixture.subgraph.ports.first { ($0 as? any ProxyPortProtocol)?.wraps(innerPort) == true })
        fixture.outer.setPublished(true, port: proxy, name: "Outer")

        switching.carriesBool = true

        let retypedInner = try #require(switching.port(forKey: .own("value")))
        #expect(retypedInner.portType == .Bool)
        let retypedProxy = try #require(fixture.subgraph.port(forKey: proxy.key))
        #expect(retypedProxy !== proxy)
        #expect(retypedProxy.portType == .Bool)
        #expect((retypedProxy as? any ProxyPortProtocol)?.wraps(retypedInner) == true)
        #expect(fixture.outer.publishedName(of: retypedProxy) == "Outer")
        #expect(fixture.subgraph.ports.firstIndex { $0 === retypedProxy } == 1)
    }
}
