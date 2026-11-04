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

    @Test("A port a document saved under the node's own key keeps its wire")
    func portSavedOutsideRegistryKeepsItsWire() throws
    {
        guard let context = makeContext() else { return }

        // The form the node saved before it declared its ports: each port at
        // the node's top level, under its coding key, with the inlet a plain
        // port that never had a parameter.
        let number = LegacyDocumentFixture.numberBinaryOperator()
        let inlet = LegacyDocumentFixture.SavedPort(key: "inputCursorPositionPort", type: "Float", name: "Pixel", savedOutsideList: true)
        let outlet = LegacyDocumentFixture.SavedPort(key: "outputUnitPositionPort", type: "Float", kind: "Outlet", name: "Unit", savedOutsideList: true)
        let units = LegacyDocumentFixture.SavedNode(type: "PixelsToUnitsNode", ports: [inlet, outlet])
        let fixture = LegacyDocumentFixture(nodes: [number.node, units], connections: [(number.output.id, inlet.id)])

        let loaded = try fixture.decode(context: context)

        let loadedNumber = try #require(loaded.node(forID: number.node.id) as? NumberBinaryOperator)
        let loadedUnits = try #require(loaded.node(forID: units.id) as? PixelsToUnitsNode)
        #expect(loadedUnits.inputCursorPosition.connectedOutlets.first === loadedNumber.outputNumber)
        #expect(loaded.droppedConnectionDiagnostics.isEmpty)
        #expect(loaded.droppedPortStateDiagnostics.isEmpty)
    }
}
