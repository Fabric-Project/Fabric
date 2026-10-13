import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

@Suite("Subgraph Embedding")
struct SubgraphEmbeddingTests
{
    enum ContainerKind: String, CaseIterable, CustomTestStringConvertible
    {
        case subgraph
        case deferredSubgraph

        var testDescription: String { rawValue }

        var nodeClass: SubgraphNode.Type
        {
            switch self
            {
            case .subgraph:
                SubgraphNode.self
            case .deferredSubgraph:
                DeferredSubgraphNode.self
            }
        }
    }

    private struct Fixture
    {
        let graph: Graph
        let upstream: NumberBinaryOperator
        let firstMovedNode: NumberBinaryOperator
        let secondMovedNode: NumberBinaryOperator
        let downstream: NumberBinaryOperator
        let incomingConnection: Connection
        let internalConnection: Connection
        let outgoingConnection: Connection
        let originalIncomingPublishedName: String
    }

    private func makeContext() -> Context?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(device: device,
                       sampleCount: 1,
                       colorPixelFormat: .bgra8Unorm,
                       depthPixelFormat: .depth32Float,
                       stencilPixelFormat: .invalid)
    }

    private func makeFixture(context: Context) throws -> Fixture
    {
        let graph = Graph(context: context)
        let upstream = NumberBinaryOperator(context: context)
        let firstMovedNode = NumberBinaryOperator(context: context)
        let secondMovedNode = NumberBinaryOperator(context: context)
        let downstream = NumberBinaryOperator(context: context)

        graph.addNode(upstream)
        graph.addNode(firstMovedNode)
        graph.addNode(secondMovedNode)
        graph.addNode(downstream)

        let incomingConnection = try #require(
            graph.connect(upstream.outputNumber, to: firstMovedNode.inputNumber1)
        )
        let internalConnection = try #require(
            graph.connect(firstMovedNode.outputNumber, to: secondMovedNode.inputNumber1)
        )
        let outgoingConnection = try #require(
            graph.connect(secondMovedNode.outputNumber, to: downstream.inputNumber1)
        )
        #expect(graph.setConnection(internalConnection, active: false))

        let originalIncomingPublishedName = "Original Boundary Name"
        graph.setPublishedName(originalIncomingPublishedName, on: firstMovedNode.inputNumber1)

        return Fixture(graph: graph,
                       upstream: upstream,
                       firstMovedNode: firstMovedNode,
                       secondMovedNode: secondMovedNode,
                       downstream: downstream,
                       incomingConnection: incomingConnection,
                       internalConnection: internalConnection,
                       outgoingConnection: outgoingConnection,
                       originalIncomingPublishedName: originalIncomingPublishedName)
    }

    private func embed(_ fixture: Fixture, as kind: ContainerKind) throws -> SubgraphNode
    {
        try fixture.graph.createSubgraph(from: [fixture.firstMovedNode, fixture.secondMovedNode],
                                         centeredOn: fixture.firstMovedNode,
                                         usingClass: kind.nodeClass)
    }

    private func expectDeferredPortsRemainIntact(on node: SubgraphNode,
                                                  sourceLocation: SourceLocation = #_sourceLocation) throws
    {
        guard let deferred = node as? DeferredSubgraphNode else { return }

        #expect(deferred.ports.contains { $0 === deferred.inputWidth }, sourceLocation: sourceLocation)
        #expect(deferred.ports.contains { $0 === deferred.inputHeight }, sourceLocation: sourceLocation)
        #expect(deferred.ports.contains { $0 === deferred.outputColorTexture }, sourceLocation: sourceLocation)
        #expect(deferred.ports.contains { $0 === deferred.outputDepthTexture }, sourceLocation: sourceLocation)
    }

    /// The wire in `graph` from the port under `outletID` to the one under
    /// `inletID`. Create Subgraph makes the wires it moves again, so a wire is
    /// found by the ports it joins rather than held across the edit.
    private func connection(in graph: Graph, from outletID: UUID, to inletID: UUID) -> Connection?
    {
        graph.connections.first { $0.outletPortID == outletID && $0.inletPortID == inletID }
    }

    /// The embedded topology, checked, as the ids of the wires in the graph and
    /// in the sub graph.
    @discardableResult
    private func expectEmbeddedTopology(_ fixture: Fixture,
                                        container: SubgraphNode,
                                        sourceLocation: SourceLocation = #_sourceLocation) throws -> Set<UUID>
    {
        #expect(fixture.graph.nodes.contains { $0 === container }, sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.graph === container.subGraph, sourceLocation: sourceLocation)
        #expect(fixture.secondMovedNode.graph === container.subGraph, sourceLocation: sourceLocation)
        #expect(container.subGraph.nodes.contains { $0 === fixture.firstMovedNode }, sourceLocation: sourceLocation)
        #expect(container.subGraph.nodes.contains { $0 === fixture.secondMovedNode }, sourceLocation: sourceLocation)

        #expect(fixture.graph.connections.count == 2, sourceLocation: sourceLocation)
        #expect(container.subGraph.connections.count == 1, sourceLocation: sourceLocation)
        let incomingConnection = try #require(
            connection(in: fixture.graph, from: fixture.upstream.outputNumber.id, to: fixture.firstMovedNode.inputNumber1.id),
            sourceLocation: sourceLocation
        )
        let internalConnection = try #require(
            connection(in: container.subGraph, from: fixture.firstMovedNode.outputNumber.id, to: fixture.secondMovedNode.inputNumber1.id),
            sourceLocation: sourceLocation
        )
        let outgoingConnection = try #require(
            connection(in: fixture.graph, from: fixture.secondMovedNode.outputNumber.id, to: fixture.downstream.inputNumber1.id),
            sourceLocation: sourceLocation
        )
        #expect(internalConnection.graph === container.subGraph, sourceLocation: sourceLocation)
        #expect(internalConnection.active == false, sourceLocation: sourceLocation)
        #expect(internalConnection.outletPort === fixture.firstMovedNode.outputNumber, sourceLocation: sourceLocation)
        #expect(internalConnection.inletPort === fixture.secondMovedNode.inputNumber1, sourceLocation: sourceLocation)

        let inletProxy = try #require(
            container.ports.first { $0.id == fixture.firstMovedNode.inputNumber1.id },
            sourceLocation: sourceLocation
        )
        let outletProxy = try #require(
            container.ports.first { $0.id == fixture.secondMovedNode.outputNumber.id },
            sourceLocation: sourceLocation
        )

        #expect(inletProxy is any ProxyPortProtocol, sourceLocation: sourceLocation)
        #expect(outletProxy is any ProxyPortProtocol, sourceLocation: sourceLocation)
        #expect(incomingConnection.inletPort === inletProxy, sourceLocation: sourceLocation)
        #expect(outgoingConnection.outletPort === outletProxy, sourceLocation: sourceLocation)
        #expect(incomingConnection.graph === fixture.graph, sourceLocation: sourceLocation)
        #expect(outgoingConnection.graph === fixture.graph, sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.inputNumber1.connections.isEmpty, sourceLocation: sourceLocation)
        #expect(fixture.secondMovedNode.outputNumber.connections.isEmpty, sourceLocation: sourceLocation)
        #expect(inletProxy.connections.count == 1 && inletProxy.connections.first === incomingConnection,
                sourceLocation: sourceLocation)
        #expect(outletProxy.connections.count == 1 && outletProxy.connections.first === outgoingConnection,
                sourceLocation: sourceLocation)
        #expect(fixture.upstream.outputNumber.connections.count == 1 && fixture.upstream.outputNumber.connections.first === incomingConnection,
                sourceLocation: sourceLocation)
        #expect(fixture.downstream.inputNumber1.connections.count == 1 && fixture.downstream.inputNumber1.connections.first === outgoingConnection,
                sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.inputNumber1.published, sourceLocation: sourceLocation)
        #expect(fixture.secondMovedNode.outputNumber.published, sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.inputNumber1.publishedName == fixture.originalIncomingPublishedName,
                sourceLocation: sourceLocation)

        try expectDeferredPortsRemainIntact(on: container, sourceLocation: sourceLocation)
        return [incomingConnection.id, internalConnection.id, outgoingConnection.id]
    }

    /// The topology before the embedding: the fixture's wires, under their
    /// own ids, on the moved nodes' own ports.
    private func expectUnembeddedTopology(_ fixture: Fixture,
                                          container: SubgraphNode,
                                          sourceLocation: SourceLocation = #_sourceLocation) throws
    {
        #expect(fixture.graph.nodes.contains { $0 === fixture.firstMovedNode }, sourceLocation: sourceLocation)
        #expect(fixture.graph.nodes.contains { $0 === fixture.secondMovedNode }, sourceLocation: sourceLocation)
        #expect(fixture.graph.nodes.contains { $0 === container } == false, sourceLocation: sourceLocation)
        #expect(Set(fixture.graph.connections.map(\.id)) == Set([
            fixture.incomingConnection.id,
            fixture.internalConnection.id,
            fixture.outgoingConnection.id,
        ]), sourceLocation: sourceLocation)

        let incomingConnection = try #require(
            fixture.graph.connections.first { $0.id == fixture.incomingConnection.id }, sourceLocation: sourceLocation
        )
        let internalConnection = try #require(
            fixture.graph.connections.first { $0.id == fixture.internalConnection.id }, sourceLocation: sourceLocation
        )
        let outgoingConnection = try #require(
            fixture.graph.connections.first { $0.id == fixture.outgoingConnection.id }, sourceLocation: sourceLocation
        )
        #expect(incomingConnection.outletPort === fixture.upstream.outputNumber, sourceLocation: sourceLocation)
        #expect(incomingConnection.inletPort === fixture.firstMovedNode.inputNumber1, sourceLocation: sourceLocation)
        #expect(internalConnection.outletPort === fixture.firstMovedNode.outputNumber, sourceLocation: sourceLocation)
        #expect(internalConnection.inletPort === fixture.secondMovedNode.inputNumber1, sourceLocation: sourceLocation)
        #expect(internalConnection.active == false, sourceLocation: sourceLocation)
        #expect(outgoingConnection.outletPort === fixture.secondMovedNode.outputNumber, sourceLocation: sourceLocation)
        #expect(outgoingConnection.inletPort === fixture.downstream.inputNumber1, sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.inputNumber1.connections.first === incomingConnection, sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.outputNumber.connections.first === internalConnection, sourceLocation: sourceLocation)
        #expect(fixture.secondMovedNode.inputNumber1.connections.first === internalConnection, sourceLocation: sourceLocation)
        #expect(fixture.secondMovedNode.outputNumber.connections.first === outgoingConnection, sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.inputNumber1.connections.count == 1, sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.outputNumber.connections.count == 1, sourceLocation: sourceLocation)
        #expect(fixture.secondMovedNode.inputNumber1.connections.count == 1, sourceLocation: sourceLocation)
        #expect(fixture.secondMovedNode.outputNumber.connections.count == 1, sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.inputNumber1.published == false, sourceLocation: sourceLocation)
        #expect(fixture.secondMovedNode.outputNumber.published == false, sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.inputNumber1.publishedName == fixture.originalIncomingPublishedName,
                sourceLocation: sourceLocation)
        #expect(!container.ports.contains { $0 is any ProxyPortProtocol }, sourceLocation: sourceLocation)
        #expect(container.subGraph.nodes.isEmpty, sourceLocation: sourceLocation)
        #expect(container.subGraph.connections.isEmpty, sourceLocation: sourceLocation)
        try expectDeferredPortsRemainIntact(on: container, sourceLocation: sourceLocation)
    }

    @Test("Creation transfers internal wires and publishes boundary proxies", arguments: ContainerKind.allCases)
    func creationTransfersConnectionsAndPublishesBoundaries(kind: ContainerKind) throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeFixture(context: context)
        let container = try embed(fixture, as: kind)

        switch kind
        {
        case .subgraph:
            #expect(type(of: container) == SubgraphNode.self)
        case .deferredSubgraph:
            #expect(container is DeferredSubgraphNode)
        }

        try expectEmbeddedTopology(fixture, container: container)
    }

    @Test("Embedding undo and redo are one stable graph edit", arguments: ContainerKind.allCases)
    func embeddingUndoRedoIsStable(kind: ContainerKind) throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeFixture(context: context)
        let undoManager = UndoManager()
        fixture.graph.undoManager = undoManager

        let container = try embed(fixture, as: kind)
        let embeddedConnectionIDs = try expectEmbeddedTopology(fixture, container: container)
        #expect(undoManager.undoActionName == "Create Subgraph")

        undoManager.undo()
        try expectUnembeddedTopology(fixture, container: container)
        #expect(undoManager.redoActionName == "Create Subgraph")

        undoManager.redo()
        #expect(try expectEmbeddedTopology(fixture, container: container) == embeddedConnectionIDs)
        #expect(undoManager.undoActionName == "Create Subgraph")

        undoManager.undo()
        try expectUnembeddedTopology(fixture, container: container)
        undoManager.redo()
        #expect(try expectEmbeddedTopology(fixture, container: container) == embeddedConnectionIDs)
        #expect(!undoManager.canRedo)
    }

    @Test("Embedded topology remains stable across two serialization round trips", arguments: ContainerKind.allCases)
    func embeddedTopologyRoundTrips(kind: ContainerKind) throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeFixture(context: context)
        let container = try embed(fixture, as: kind)

        let expectedConnectionIDs = try expectEmbeddedTopology(fixture, container: container)
        let internalConnectionID = try #require(container.subGraph.connections.first?.id)
        let incomingConnectionID = try #require(
            connection(in: fixture.graph, from: fixture.upstream.outputNumber.id, to: fixture.firstMovedNode.inputNumber1.id)?.id
        )
        let outgoingConnectionID = try #require(
            connection(in: fixture.graph, from: fixture.secondMovedNode.outputNumber.id, to: fixture.downstream.inputNumber1.id)?.id
        )
        var encodedGraph = try JSONEncoder().encode(fixture.graph)

        for _ in 0..<2
        {
            let decoder = JSONDecoder()
            decoder.context = DecoderContext(documentContext: context)
            let decodedGraph = try decoder.decode(Graph.self, from: encodedGraph)
            let decodedContainer = try #require(
                decodedGraph.nodes.first { $0.id == container.id } as? SubgraphNode
            )
            let decodedFirstMovedNode = try #require(
                decodedContainer.subGraph.nodes.first { $0.id == fixture.firstMovedNode.id } as? NumberBinaryOperator
            )
            let decodedSecondMovedNode = try #require(
                decodedContainer.subGraph.nodes.first { $0.id == fixture.secondMovedNode.id } as? NumberBinaryOperator
            )

            #expect(decodedGraph.connections.count == 2)
            #expect(decodedContainer.subGraph.connections.count == 1)
            #expect(Set(decodedGraph.connections.map(\.id))
                    .union(decodedContainer.subGraph.connections.map(\.id)) == expectedConnectionIDs)

            let decodedInternalConnection = try #require(decodedContainer.subGraph.connections.first)
            #expect(decodedInternalConnection.id == internalConnectionID)
            #expect(decodedInternalConnection.graph === decodedContainer.subGraph)
            #expect(decodedInternalConnection.active == false)
            #expect(decodedInternalConnection.outletPort === decodedFirstMovedNode.outputNumber)
            #expect(decodedInternalConnection.inletPort === decodedSecondMovedNode.inputNumber1)

            let decodedInletProxy = try #require(
                decodedContainer.ports.first { $0.id == decodedFirstMovedNode.inputNumber1.id }
            )
            let decodedOutletProxy = try #require(
                decodedContainer.ports.first { $0.id == decodedSecondMovedNode.outputNumber.id }
            )
            let decodedIncomingConnection = try #require(
                decodedGraph.connections.first { $0.id == incomingConnectionID }
            )
            let decodedOutgoingConnection = try #require(
                decodedGraph.connections.first { $0.id == outgoingConnectionID }
            )

            #expect(decodedInletProxy is any ProxyPortProtocol)
            #expect(decodedOutletProxy is any ProxyPortProtocol)
            #expect(decodedIncomingConnection.inletPort === decodedInletProxy)
            #expect(decodedOutgoingConnection.outletPort === decodedOutletProxy)
            #expect(decodedIncomingConnection.graph === decodedGraph)
            #expect(decodedOutgoingConnection.graph === decodedGraph)
            #expect(decodedInletProxy.connections == [decodedIncomingConnection])
            #expect(decodedOutletProxy.connections == [decodedOutgoingConnection])
            #expect(decodedFirstMovedNode.inputNumber1.connections.isEmpty)
            #expect(decodedSecondMovedNode.outputNumber.connections.isEmpty)
            #expect(decodedFirstMovedNode.inputNumber1.published)
            #expect(decodedSecondMovedNode.outputNumber.published)
            #expect(decodedFirstMovedNode.inputNumber1.publishedName == fixture.originalIncomingPublishedName)
            #expect(decodedGraph.droppedConnectionDiagnostics.isEmpty)
            #expect(decodedContainer.subGraph.droppedConnectionDiagnostics.isEmpty)
            try expectDeferredPortsRemainIntact(on: decodedContainer)

            encodedGraph = try JSONEncoder().encode(decodedGraph)
        }
    }

    @Test("A boundary port published here under a name keeps that name inside, through undo and redo", arguments: ContainerKind.allCases)
    func boundaryPortKeepsItsPublishedName(kind: ContainerKind) throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeFixture(context: context)
        let port = fixture.secondMovedNode.outputNumber
        fixture.graph.setPublished(true, on: port)
        fixture.graph.setPublishedName("Gain", on: port)
        let undoManager = UndoManager()
        fixture.graph.undoManager = undoManager

        func expectNamedInside(_ container: SubgraphNode, _ comment: Comment)
        {
            #expect(port.published && port.publishedName == "Gain", comment)
            #expect(container.ports.contains { $0.id == port.id && $0 is any ProxyPortProtocol && $0.displayName == "Gain" }, comment)
        }

        let container = try embed(fixture, as: kind)
        expectNamedInside(container, "created")

        undoManager.undo()
        #expect(port.node?.graph === fixture.graph)
        #expect(port.published && port.publishedName == "Gain", "undone")

        undoManager.redo()
        expectNamedInside(container, "redone")
    }

    @Test("A port unpublished and published again by undo has its new proxy take the parent's wire back", arguments: ContainerKind.allCases)
    func republishedPortTakesParentWireBack(kind: ContainerKind) throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeFixture(context: context)
        let container = try embed(fixture, as: kind)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        fixture.graph.undoManager = undoManager

        let innerPort = fixture.firstMovedNode.inputNumber1
        // Held across the republish, which keeps the dropped proxy alive: the
        // wire must come back on the new proxy, not on this live object that
        // no longer belongs to the node.
        let originalProxy = try #require(container.ports.first { $0.id == innerPort.id })
        let incomingConnection = try #require(
            connection(in: fixture.graph, from: fixture.upstream.outputNumber.id, to: innerPort.id)
        )
        #expect(incomingConnection.inletPort === originalProxy)

        undoManager.beginUndoGrouping()
        container.subGraph.setPublished(false, on: innerPort)
        undoManager.endUndoGrouping()
        #expect(!container.ports.contains { $0.id == innerPort.id })

        undoManager.undo()

        let rebuiltProxy = try #require(container.ports.first { $0.id == innerPort.id })
        #expect(rebuiltProxy !== originalProxy)
        let wire = try #require(fixture.graph.connections.first { $0.id == incomingConnection.id })
        #expect(wire.inletPort === rebuiltProxy)
        #expect(rebuiltProxy.connections.map(\.id) == [wire.id])
        #expect(originalProxy.connections.isEmpty)
        #expect(fixture.graph.connections.filter { $0.id == wire.id }.count == 1)
        undoManager.beginUndoGrouping()
        #expect(fixture.graph.disconnect(wire))
        undoManager.endUndoGrouping()
    }

    @Test("Unpublishing a port takes the parent's wires onto its proxy with it", arguments: ContainerKind.allCases)
    func unpublishingTakesTheParentWires(kind: ContainerKind) throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeFixture(context: context)
        let container = try embed(fixture, as: kind)

        let innerPort = fixture.firstMovedNode.inputNumber1
        let proxy = try #require(container.ports.first { $0.id == innerPort.id })
        let incomingConnection = try #require(
            connection(in: fixture.graph, from: fixture.upstream.outputNumber.id, to: innerPort.id)
        )
        #expect(incomingConnection.inletPort === proxy)

        container.subGraph.setPublished(false, on: innerPort)

        // The proxy has gone, and so has the wire that named it: not left in
        // the graph, not left on the port at the other end.
        #expect(!container.ports.contains { $0.id == innerPort.id })
        #expect(!fixture.graph.connections.contains { $0.id == incomingConnection.id })
        #expect(fixture.upstream.outputNumber.connections.isEmpty)
        #expect(innerPort.published == false)
        #expect(innerPort.publishedName == nil)

        // Publishing again brings a proxy back, with nothing wired to it.
        container.subGraph.setPublished(true, on: innerPort)
        let rebuilt = try #require(container.ports.first { $0.id == innerPort.id })
        #expect(rebuilt.connections.isEmpty)
    }
}
