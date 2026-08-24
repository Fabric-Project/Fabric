import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

@Suite("Graph Connection Ownership")
struct GraphConnectionOwnershipTests
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

    @Test("Graph owns connection mutation and rejects foreign endpoints atomically")
    func graphOwnsConnectionMutation() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let source = NumberBinaryOperator(context: context)
        let sink = NumberBinaryOperator(context: context)
        graph.addNode(source)
        graph.addNode(sink)

        let connection = try #require(graph.connect(source.outputNumber, to: sink.inputNumber1))
        #expect(graph.connections == [connection])
        #expect(connection.graph === graph)
        #expect(source.outputNumber.connections == [connection])
        #expect(sink.inputNumber1.connections == [connection])
        #expect(source.outputNodes.contains { $0 === sink })
        #expect(sink.inputNodes.contains { $0 === source })

        let duplicate = try #require(graph.connect(source.outputNumber, to: sink.inputNumber1))
        #expect(duplicate === connection)
        #expect(graph.connections.count == 1)

        let otherGraph = Graph(context: context)
        let foreignSink = NumberBinaryOperator(context: context)
        otherGraph.addNode(foreignSink)
        #expect(graph.connect(source.outputNumber, to: foreignSink.inputNumber1) == nil)
        #expect(graph.connections == [connection])
        #expect(foreignSink.inputNumber1.connections.isEmpty)

        #expect(graph.disconnect(connection))
        #expect(graph.connections.isEmpty)
        #expect(connection.graph == nil)
        #expect(source.outputNumber.connections.isEmpty)
        #expect(sink.inputNumber1.connections.isEmpty)
        #expect(source.outputNodes.isEmpty)
        #expect(sink.inputNodes.isEmpty)
    }

    @Test("Replacing an inlet is one undoable graph edit")
    func inletReplacementUndoRedo() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let firstSource = NumberBinaryOperator(context: context)
        let secondSource = NumberBinaryOperator(context: context)
        let sink = NumberBinaryOperator(context: context)
        graph.addNode(firstSource)
        graph.addNode(secondSource)
        graph.addNode(sink)
        let firstConnection = try #require(graph.connect(firstSource.outputNumber, to: sink.inputNumber1))

        let undoManager = UndoManager()
        graph.undoManager = undoManager
        let secondConnection = try #require(graph.connect(secondSource.outputNumber, to: sink.inputNumber1))
        #expect(graph.connections == [secondConnection])

        undoManager.undo()
        #expect(graph.connections == [firstConnection])
        #expect(firstConnection.graph === graph)
        #expect(secondConnection.graph == nil)

        undoManager.redo()
        #expect(graph.connections == [secondConnection])
        #expect(firstConnection.graph == nil)
        #expect(secondConnection.graph === graph)

        undoManager.undo()
        undoManager.redo()
        #expect(graph.connections == [secondConnection])
        #expect(sink.inputNumber1.connections == [secondConnection])
    }

    @Test("Parameter insertion preserves the original wire through undo and redo")
    func parameterInsertionUndoRedo() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let source = NumberBinaryOperator(context: context)
        let sink = NumberBinaryOperator(context: context)
        graph.addNode(source)
        graph.addNode(sink)
        let originalConnection = try #require(graph.connect(source.outputNumber, to: sink.inputNumber1))

        let undoManager = UndoManager()
        graph.undoManager = undoManager
        graph.insertParameterNode(for: sink.inputNumber1)

        let parameterNode = try #require(graph.nodes.first { $0 !== source && $0 !== sink })
        #expect(parameterNode is PassThroughNode<Float>)
        #expect(graph.connections.count == 2)
        #expect(originalConnection.graph == nil)
        #expect(source.outputNumber.connectedPorts.first?.node === parameterNode)
        #expect(sink.inputNumber1.connectedPorts.first?.node === parameterNode)

        undoManager.undo()
        #expect(graph.nodes.count == 2)
        #expect(graph.connections == [originalConnection])
        #expect(originalConnection.graph === graph)
        #expect(source.outputNumber.connectedPorts == [sink.inputNumber1])

        undoManager.redo()
        #expect(graph.nodes.contains { $0 === parameterNode })
        #expect(graph.connections.count == 2)
        #expect(source.outputNumber.connectedPorts.first?.node === parameterNode)
        #expect(sink.inputNumber1.connectedPorts.first?.node === parameterNode)
    }

    @Test("Disconnecting one outlet wire leaves sibling values intact")
    func disconnectOnlyClearsItsInlet() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let source = NumberBinaryOperator(context: context)
        let firstSink = NumberBinaryOperator(context: context)
        let secondSink = NumberBinaryOperator(context: context)
        graph.addNode(source)
        graph.addNode(firstSink)
        graph.addNode(secondSink)
        graph.connect(source.outputNumber, to: firstSink.inputNumber1)
        graph.connect(source.outputNumber, to: secondSink.inputNumber1)
        source.outputNumber.send(42)

        #expect(graph.disconnect(source.outputNumber, from: firstSink.inputNumber1))
        #expect(firstSink.inputNumber1.connections.isEmpty)
        #expect(secondSink.inputNumber1.value == 42)
        #expect(secondSink.inputNumber1.connections.count == 1)
    }

    @Test("Disconnect all and active state changes undo through Graph")
    func disconnectAllAndActiveStateUndo() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let source = NumberBinaryOperator(context: context)
        let firstSink = NumberBinaryOperator(context: context)
        let secondSink = NumberBinaryOperator(context: context)
        graph.addNode(source)
        graph.addNode(firstSink)
        graph.addNode(secondSink)
        let firstConnection = try #require(graph.connect(source.outputNumber, to: firstSink.inputNumber1))
        let secondConnection = try #require(graph.connect(source.outputNumber, to: secondSink.inputNumber1))

        let undoManager = UndoManager()
        graph.undoManager = undoManager
        #expect(graph.setConnection(firstConnection, active: false))
        #expect(!firstConnection.active)
        undoManager.undo()
        #expect(firstConnection.active)
        undoManager.redo()
        #expect(!firstConnection.active)

        undoManager.removeAllActions()
        graph.disconnectAll(from: source.outputNumber)
        #expect(graph.connections.isEmpty)
        undoManager.undo()
        #expect(Set(graph.connections) == Set([firstConnection, secondConnection]))
        #expect(source.outputNumber.connections.count == 2)
        undoManager.redo()
        #expect(graph.connections.isEmpty)
    }

    @Test("Graph connection records are authoritative and exclusively encoded")
    func graphConnectionsAreTheSerializationAuthority() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let source = NumberBinaryOperator(context: context)
        let sink = NumberBinaryOperator(context: context)
        graph.addNode(source)
        graph.addNode(sink)
        graph.connect(source.outputNumber, to: sink.inputNumber1)

        let encoded = try JSONEncoder().encode(graph)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let connectionRecords = try #require(object["connections"] as? [[String: Any]])
        #expect(connectionRecords.count == 1)
        #expect(object["portConnectionMap"] == nil)

        let encodedPort = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source.outputNumber)) as? [String: Any]
        #expect(encodedPort?["connections"] == nil)

        object["portConnectionMap"] = [
            source.outputNumber.id.uuidString,
            [sink.inputNumber1.id.uuidString],
            sink.inputNumber1.id.uuidString,
            [source.outputNumber.id.uuidString]
        ]

        object["connections"] = []
        let authoritativeEmptyData = try JSONSerialization.data(withJSONObject: object)
        let authoritativeEmptyDecoder = JSONDecoder()
        authoritativeEmptyDecoder.context = DecoderContext(documentContext: context)
        let authoritativeEmptyGraph = try authoritativeEmptyDecoder.decode(Graph.self, from: authoritativeEmptyData)
        #expect(authoritativeEmptyGraph.connections.isEmpty)
    }

    @Test("Legacy port connection maps migrate to graph connection records")
    func legacyPortConnectionsMigrateToGraphConnections() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let source = NumberBinaryOperator(context: context)
        let sink = NumberBinaryOperator(context: context)
        graph.addNode(source)
        graph.addNode(sink)
        graph.connect(source.outputNumber, to: sink.inputNumber1)

        var legacyObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(graph)) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "connections")
        legacyObject["portConnectionMap"] = [
            source.outputNumber.id.uuidString,
            [sink.inputNumber1.id.uuidString],
            sink.inputNumber1.id.uuidString,
            [source.outputNumber.id.uuidString]
        ]

        // Legacy documents redundantly stored connected port identifiers in
        // each port snapshot as well as in the graph-level port map.
        var legacyNodeMap = try #require(legacyObject["nodeMap"] as? [[String: Any]])
        var legacyPortConnectionFieldCount = 0
        for nodeIndex in legacyNodeMap.indices
        {
            guard var value = legacyNodeMap[nodeIndex]["value"] as? [String: Any],
                  var ports = value["ports"] as? [[String: Any]]
            else { continue }

            for portIndex in ports.indices
            {
                guard var payload = ports[portIndex]["payload"] as? [String: Any],
                      var base = payload["base"] as? [String: Any],
                      let portID = base["id"] as? String
                else { continue }

                if portID == source.outputNumber.id.uuidString {
                    base["connections"] = [sink.inputNumber1.id.uuidString]
                    legacyPortConnectionFieldCount += 1
                }
                else if portID == sink.inputNumber1.id.uuidString {
                    base["connections"] = [source.outputNumber.id.uuidString]
                    legacyPortConnectionFieldCount += 1
                }
                else {
                    continue
                }

                payload["base"] = base
                ports[portIndex]["payload"] = payload
            }

            value["ports"] = ports
            legacyNodeMap[nodeIndex]["value"] = value
        }
        #expect(legacyPortConnectionFieldCount == 2)
        legacyObject["nodeMap"] = legacyNodeMap

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(Graph.self, from: legacyData)
        #expect(decoded.connections.count == 1)
        #expect(decoded.connections[0].graph === decoded)
        #expect(decoded.connections[0].outletPort?.connections.count == 1)
        #expect(decoded.connections[0].inletPort?.connections.count == 1)

        let migratedConnectionID = decoded.connections[0].id
        let modernData = try JSONEncoder().encode(decoded)
        let modernObject = try #require(JSONSerialization.jsonObject(with: modernData) as? [String: Any])
        let modernConnections = try #require(modernObject["connections"] as? [[String: Any]])
        #expect(modernConnections.count == 1)
        #expect(modernConnections[0]["id"] as? String == migratedConnectionID.uuidString)
        #expect(modernObject["portConnectionMap"] == nil)

        let modernNodeMap = try #require(modernObject["nodeMap"] as? [[String: Any]])
        for entry in modernNodeMap
        {
            guard let value = entry["value"] as? [String: Any],
                  let ports = value["ports"] as? [[String: Any]]
            else { continue }

            for port in ports
            {
                let payload = port["payload"] as? [String: Any]
                let base = payload?["base"] as? [String: Any]
                #expect(base?["connections"] == nil)
            }
        }

        let modernDecoder = JSONDecoder()
        modernDecoder.context = DecoderContext(documentContext: context)
        let modernGraph = try modernDecoder.decode(Graph.self, from: modernData)
        #expect(modernGraph.connections.count == 1)
        #expect(modernGraph.connections[0].id == migratedConnectionID)
        #expect(modernGraph.connections[0].graph === modernGraph)
        #expect(modernGraph.connections[0].outletPort?.connections == modernGraph.connections)
        #expect(modernGraph.connections[0].inletPort?.connections == modernGraph.connections)
    }

    @Test("Dynamic port replacement preserves wires through undo and redo")
    func dynamicPortReplacementUndoRedo() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let source = SwitchNode(context: context, routeCount: 2, portType: .Virtual)
        let changed = SwitchNode(context: context, routeCount: 2, portType: .Virtual)
        let log = LogNode(context: context)
        graph.addNode(source)
        graph.addNode(changed)
        graph.addNode(log)
        let originalInput = try #require(changed.findPort(named: "input0", as: Port.self))
        graph.connect(source.output, to: originalInput)
        graph.connect(changed.output, to: log.inputAny)

        let undoManager = UndoManager()
        graph.undoManager = undoManager
        changed.setPortType(.Float)
        #expect(changed.output.portType == .Float)
        #expect(graph.connections.count == 2)

        undoManager.undo()
        #expect(changed.output.portType == .Virtual)
        #expect(graph.connections.count == 2)
        #expect(changed.output.connections.count == 1)
        #expect(changed.findPort(named: "input0", as: Port.self)?.connections.count == 1)

        undoManager.redo()
        #expect(changed.output.portType == .Float)
        #expect(graph.connections.count == 2)
        #expect(changed.output.connections.count == 1)
        #expect(changed.findPort(named: "input0", as: Port.self)?.connections.count == 1)
    }

    @Test("Node deletion restores graph-owned wires without duplicates")
    func nodeDeletionUndoRedo() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let source = NumberBinaryOperator(context: context)
        let sink = NumberBinaryOperator(context: context)
        graph.addNode(source)
        graph.addNode(sink)
        let connection = try #require(graph.connect(source.outputNumber, to: sink.inputNumber1))

        let undoManager = UndoManager()
        graph.undoManager = undoManager
        graph.delete(node: source)
        #expect(!graph.nodes.contains { $0 === source })
        #expect(graph.connections.isEmpty)

        undoManager.undo()
        #expect(graph.nodes.contains { $0 === source })
        #expect(graph.connections == [connection])
        #expect(source.outputNumber.connections == [connection])

        undoManager.redo()
        #expect(!graph.nodes.contains { $0 === source })
        #expect(graph.connections.isEmpty)

        undoManager.undo()
        #expect(graph.connections == [connection])
        #expect(source.outputNumber.connections == [connection])
        #expect(sink.inputNumber1.connections == [connection])
    }

    @Test("Embedding transfers internal wires and undo restores their identity")
    func embeddingTransfersInternalConnections() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let source = NumberBinaryOperator(context: context)
        let sink = NumberBinaryOperator(context: context)
        graph.addNode(source)
        graph.addNode(sink)
        let connection = try #require(graph.connect(source.outputNumber, to: sink.inputNumber1))
        #expect(graph.setConnection(connection, active: false))

        let undoManager = UndoManager()
        graph.undoManager = undoManager
        let revisionBeforeEmbedding = graph.connectionRevision
        let subgraphNode = try graph.createSubgraph(from: [source, sink],
                                                    centeredOn: source,
                                                    usingClass: SubgraphNode.self)
        #expect(graph.connectionRevision == revisionBeforeEmbedding + 1)
        #expect(graph.connections.isEmpty)
        #expect(subgraphNode.subGraph.connections == [connection])
        #expect(connection.graph === subgraphNode.subGraph)
        #expect(!connection.active)

        let canvasContext = GraphCanvasContext(rootGraph: graph)
        canvasContext.enter(subgraphNode)
        let pairs = canvasContext.connectionPairs(for: canvasContext.currentGraph)
        #expect(pairs.count == 1)
        #expect(pairs.first?.connection === connection)

        let encoded = try JSONEncoder().encode(graph)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(Graph.self, from: encoded)
        let decodedSubgraph = try #require(decoded.nodes.first { $0.id == subgraphNode.id } as? SubgraphNode)
        let decodedConnection = try #require(decodedSubgraph.subGraph.connections.first)
        #expect(decoded.connections.isEmpty)
        #expect(decodedConnection.id == connection.id)
        #expect(decodedConnection.graph === decodedSubgraph.subGraph)
        #expect(!decodedConnection.active)

        let revisionBeforeUndo = graph.connectionRevision
        undoManager.undo()
        #expect(graph.connectionRevision == revisionBeforeUndo + 1)
        #expect(graph.nodes.contains { $0 === source })
        #expect(graph.nodes.contains { $0 === sink })
        #expect(graph.connections == [connection])
        #expect(connection.graph === graph)

        let revisionBeforeRedo = graph.connectionRevision
        undoManager.redo()
        #expect(graph.connectionRevision == revisionBeforeRedo + 1)
        #expect(graph.nodes.contains { $0 === subgraphNode })
        #expect(subgraphNode.subGraph.connections == [connection])
        #expect(connection.graph === subgraphNode.subGraph)
    }

    @Test("Invalid subgraph selections use the shared Fabric graph error domain")
    func invalidSubgraphSelectionsUseFabricError() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let graphNode = NumberBinaryOperator(context: context)
        graph.addNode(graphNode)

        do
        {
            _ = try graph.createSubgraph(from: [],
                                         centeredOn: graphNode,
                                         usingClass: SubgraphNode.self)
            Issue.record("Expected an empty-selection error")
        }
        catch let error as FabricError
        {
            #expect(error.kind == .graph(.emptyNodeSelection))
            #expect(error.severity == .recoverable)
        }

        let foreignNode = NumberBinaryOperator(context: context)
        do
        {
            _ = try graph.createSubgraph(from: [foreignNode],
                                         centeredOn: foreignNode,
                                         usingClass: SubgraphNode.self)
            Issue.record("Expected a node-ownership error")
        }
        catch let error as FabricError
        {
            #expect(error.kind == .graph(.nodeNotInGraph))
            #expect(error.severity == .recoverable)
            #expect(error.localizedDescription.contains(foreignNode.id.uuidString))
        }
    }

    @Test("Embedding rebinds incoming and outgoing boundaries to proxies")
    func embeddingRebindsBoundaryConnections() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let upstream = NumberBinaryOperator(context: context)
        let moved = NumberBinaryOperator(context: context)
        let downstream = NumberBinaryOperator(context: context)
        graph.addNode(upstream)
        graph.addNode(moved)
        graph.addNode(downstream)
        let incoming = try #require(graph.connect(upstream.outputNumber, to: moved.inputNumber1))
        let outgoing = try #require(graph.connect(moved.outputNumber, to: downstream.inputNumber1))

        let undoManager = UndoManager()
        graph.undoManager = undoManager
        let subgraphNode = try graph.createSubgraph(from: [moved],
                                                    centeredOn: moved,
                                                    usingClass: SubgraphNode.self)
        let inletProxy = try #require(subgraphNode.ports.first { $0.id == moved.inputNumber1.id })
        let outletProxy = try #require(subgraphNode.ports.first { $0.id == moved.outputNumber.id })

        #expect(inletProxy is any ProxyPortProtocol)
        #expect(outletProxy is any ProxyPortProtocol)
        #expect(incoming.inletPort === inletProxy)
        #expect(outgoing.outletPort === outletProxy)
        #expect(moved.inputNumber1.connections.isEmpty)
        #expect(moved.outputNumber.connections.isEmpty)
        #expect(graph.connections.count == 2)
        #expect(subgraphNode.subGraph.connections.isEmpty)
        #expect(upstream.outputNodes.contains { $0 === subgraphNode })
        #expect(downstream.inputNodes.contains { $0 === subgraphNode })

        upstream.outputNumber.send(21)
        #expect(moved.inputNumber1.value == 21)

        undoManager.undo()
        #expect(incoming.inletPort === moved.inputNumber1)
        #expect(outgoing.outletPort === moved.outputNumber)
        #expect(!moved.inputNumber1.published)
        #expect(!moved.outputNumber.published)
        #expect(moved.inputNumber1.connections == [incoming])
        #expect(moved.outputNumber.connections == [outgoing])

        undoManager.redo()
        #expect(incoming.inletPort?.node === subgraphNode)
        #expect(outgoing.outletPort?.node === subgraphNode)
        #expect(graph.connections.count == 2)
    }
}
