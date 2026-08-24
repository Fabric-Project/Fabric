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
        firstMovedNode.inputNumber1.published = false
        firstMovedNode.inputNumber1.publishedName = originalIncomingPublishedName
        secondMovedNode.outputNumber.published = false

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

    private func expectEmbeddedTopology(_ fixture: Fixture,
                                        container: SubgraphNode,
                                        sourceLocation: SourceLocation = #_sourceLocation) throws
    {
        #expect(fixture.graph.nodes.contains { $0 === container }, sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.graph === container.subGraph, sourceLocation: sourceLocation)
        #expect(fixture.secondMovedNode.graph === container.subGraph, sourceLocation: sourceLocation)
        #expect(container.subGraph.nodes.contains { $0 === fixture.firstMovedNode }, sourceLocation: sourceLocation)
        #expect(container.subGraph.nodes.contains { $0 === fixture.secondMovedNode }, sourceLocation: sourceLocation)

        #expect(fixture.graph.connections.count == 2, sourceLocation: sourceLocation)
        #expect(Set(fixture.graph.connections) == Set([
            fixture.incomingConnection,
            fixture.outgoingConnection,
        ]), sourceLocation: sourceLocation)
        #expect(container.subGraph.connections == [fixture.internalConnection], sourceLocation: sourceLocation)
        #expect(fixture.internalConnection.graph === container.subGraph, sourceLocation: sourceLocation)
        #expect(fixture.internalConnection.active == false, sourceLocation: sourceLocation)

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
        #expect(fixture.incomingConnection.inletPort === inletProxy, sourceLocation: sourceLocation)
        #expect(fixture.outgoingConnection.outletPort === outletProxy, sourceLocation: sourceLocation)
        #expect(fixture.incomingConnection.graph === fixture.graph, sourceLocation: sourceLocation)
        #expect(fixture.outgoingConnection.graph === fixture.graph, sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.inputNumber1.connections.isEmpty, sourceLocation: sourceLocation)
        #expect(fixture.secondMovedNode.outputNumber.connections.isEmpty, sourceLocation: sourceLocation)
        #expect(inletProxy.connections == [fixture.incomingConnection], sourceLocation: sourceLocation)
        #expect(outletProxy.connections == [fixture.outgoingConnection], sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.inputNumber1.published, sourceLocation: sourceLocation)
        #expect(fixture.secondMovedNode.outputNumber.published, sourceLocation: sourceLocation)
        #expect(fixture.firstMovedNode.inputNumber1.publishedName == fixture.originalIncomingPublishedName,
                sourceLocation: sourceLocation)

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
        try expectEmbeddedTopology(fixture, container: container)

        undoManager.undo()

        #expect(fixture.graph.nodes.contains { $0 === fixture.firstMovedNode })
        #expect(fixture.graph.nodes.contains { $0 === fixture.secondMovedNode })
        #expect(fixture.graph.nodes.contains { $0 === container } == false)
        #expect(Set(fixture.graph.connections) == Set([
            fixture.incomingConnection,
            fixture.internalConnection,
            fixture.outgoingConnection,
        ]))
        #expect(fixture.incomingConnection.inletPort === fixture.firstMovedNode.inputNumber1)
        #expect(fixture.internalConnection.outletPort === fixture.firstMovedNode.outputNumber)
        #expect(fixture.internalConnection.inletPort === fixture.secondMovedNode.inputNumber1)
        #expect(fixture.outgoingConnection.outletPort === fixture.secondMovedNode.outputNumber)
        #expect(fixture.firstMovedNode.inputNumber1.connections == [fixture.incomingConnection])
        #expect(fixture.firstMovedNode.outputNumber.connections == [fixture.internalConnection])
        #expect(fixture.secondMovedNode.inputNumber1.connections == [fixture.internalConnection])
        #expect(fixture.secondMovedNode.outputNumber.connections == [fixture.outgoingConnection])
        #expect(fixture.firstMovedNode.inputNumber1.published == false)
        #expect(fixture.secondMovedNode.outputNumber.published == false)
        #expect(fixture.firstMovedNode.inputNumber1.publishedName == fixture.originalIncomingPublishedName)
        try expectDeferredPortsRemainIntact(on: container)

        undoManager.redo()
        try expectEmbeddedTopology(fixture, container: container)

        undoManager.undo()
        undoManager.redo()
        try expectEmbeddedTopology(fixture, container: container)
    }

    @Test("Embedded topology remains stable across two serialization round trips", arguments: ContainerKind.allCases)
    func embeddedTopologyRoundTrips(kind: ContainerKind) throws
    {
        guard let context = makeContext() else { return }
        let fixture = try makeFixture(context: context)
        let container = try embed(fixture, as: kind)

        let expectedConnectionIDs = Set([
            fixture.incomingConnection.id,
            fixture.internalConnection.id,
            fixture.outgoingConnection.id,
        ])
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
            #expect(decodedInternalConnection.id == fixture.internalConnection.id)
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
                decodedGraph.connections.first { $0.id == fixture.incomingConnection.id }
            )
            let decodedOutgoingConnection = try #require(
                decodedGraph.connections.first { $0.id == fixture.outgoingConnection.id }
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
}
