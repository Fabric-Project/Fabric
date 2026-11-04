import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// A node that holds a port in a stored property declares that port, so the
/// property and the registry name one object, under the key documents saved
/// it by.
@Suite("Stored port declarations")
struct StoredPortDeclarationTests
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

    @Test("A stored port is the registry's port under its saved key")
    func storedPortIsRegistered() throws
    {
        guard let context = makeContext() else { return }

        let log = LogNode(context: context)
        let registered: Fabric.Port? = log.findPort(named: "inputAnyPort")
        #expect(registered === log.inputAny)
        #expect(log.ports.count == 1)

        let units = PixelsToUnitsNode(context: context)
        #expect((units.findPort(named: "inputCursorPositionPort") as Fabric.Port?) === units.inputCursorPosition)
        #expect((units.findPort(named: "outputUnitPositionPort") as Fabric.Port?) === units.outputUnitPosition)
        #expect(units.ports.map(\.id) == [units.inputCursorPosition.id, units.outputUnitPosition.id])
        #expect(units.parameterGroup.params.contains { $0 === units.inputCursorPosition.parameter })
    }

    @Test("A port a document saved under the node's own key keeps its identity and wire")
    func portSavedOutsideRegistryHydrates() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let number = NumberBinaryOperator(context: context)
        let units = PixelsToUnitsNode(context: context)
        graph.addNode(number)
        graph.addNode(units)
        graph.connect(number.outputNumber, to: units.inputCursorPosition)
        units.inputCursorPosition.value = 40
        let savedInletID = units.inputCursorPosition.id
        let savedOutletID = units.outputUnitPosition.id

        // Rewrite the document into the form the node saved before it declared
        // its ports: each port at the node's top level, under its coding key,
        // with the inlet a plain port that never had a parameter.
        let data = try JSONEncoder().encode(graph)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var nodeMap = try #require(object["nodeMap"] as? [[String: Any]])
        let index = try #require(nodeMap.firstIndex { ($0["value"] as? [String: Any])?["id"] as? String == units.id.uuidString })
        var value = try #require(nodeMap[index]["value"] as? [String: Any])
        let snapshots = try #require(value["ports"] as? [[String: Any]])
        for snapshot in snapshots
        {
            let key = try #require(snapshot["name"] as? String)
            let payload = try #require(snapshot["payload"] as? [String: Any])
            value[key] = payload["base"]
        }
        let legacyInlet = NodePort<Float>(name: "Pixel", kind: .Inlet, id: savedInletID)
        value["inputCursorPositionPort"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyInlet))
        value["ports"] = []
        nodeMap[index]["value"] = value
        object["nodeMap"] = nodeMap

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let loaded = try decoder.decode(Graph.self, from: JSONSerialization.data(withJSONObject: object))

        let loadedUnits = try #require(loaded.node(forID: units.id) as? PixelsToUnitsNode)
        #expect(loadedUnits.inputCursorPosition.id == savedInletID)
        #expect(loadedUnits.outputUnitPosition.id == savedOutletID)
        #expect(loadedUnits.inputCursorPosition.connectedOutlets.map(\.id) == [number.outputNumber.id])
        #expect(loaded.droppedConnectionDiagnostics.isEmpty)
        #expect(loaded.droppedPortStateDiagnostics.isEmpty)
    }
}
