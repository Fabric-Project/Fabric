import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// An edit's name stands on the Undo item after it, on the Redo item after
/// its undo, and on the Undo item again after its redo, however many steps
/// it registers and whatever their handlers name.
@Suite("Undo Action Names")
struct UndoActionNameTests
{
    private struct Fixture
    {
        let graph: Graph
        let upstream: NumberBinaryOperator
        let downstream: NumberBinaryOperator
        let undoManager: UndoManager
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

    /// Two nodes, the root's undo manager not grouping by event, as the other
    /// undo fixtures have it.
    private func makeFixture(context: Context) -> Fixture
    {
        let graph = Graph(context: context)
        let upstream = NumberBinaryOperator(context: context)
        let downstream = NumberBinaryOperator(context: context)
        graph.addNode(upstream)
        graph.addNode(downstream)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        graph.undoManager = undoManager
        return Fixture(graph: graph, upstream: upstream, downstream: downstream, undoManager: undoManager)
    }

    /// One edit per group, as the editor's event loop makes them.
    private func step(_ undoManager: UndoManager, _ edit: () -> Void)
    {
        undoManager.beginUndoGrouping()
        edit()
        undoManager.endUndoGrouping()
    }

    /// Makes `edit` as one top-level group, then checks it is named `name`
    /// after it, after its undo, after its redo, and through a second undo
    /// and redo. Leaves the edit made.
    private func expectNamed(_ name: String,
                             _ undoManager: UndoManager,
                             sourceLocation: SourceLocation = #_sourceLocation,
                             _ edit: () -> Void)
    {
        step(undoManager, edit)
        expectNamedThroughUndoAndRedo(name, undoManager, sourceLocation: sourceLocation)
    }

    private func expectNamedThroughUndoAndRedo(_ name: String,
                                               _ undoManager: UndoManager,
                                               sourceLocation: SourceLocation = #_sourceLocation)
    {
        #expect(undoManager.undoActionName == name, "made", sourceLocation: sourceLocation)
        undoManager.undo()
        #expect(undoManager.redoActionName == name, "undone", sourceLocation: sourceLocation)
        undoManager.redo()
        #expect(undoManager.undoActionName == name, "redone", sourceLocation: sourceLocation)
        undoManager.undo()
        #expect(undoManager.redoActionName == name, "undone after a redo", sourceLocation: sourceLocation)
        undoManager.redo()
        #expect(undoManager.undoActionName == name, "redone again", sourceLocation: sourceLocation)
    }

    @Test("Connecting a wire")
    func connect()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        expectNamed("Connect Ports", fixture.undoManager) {
            fixture.graph.connect(fixture.upstream.outputNumber, to: fixture.downstream.inputNumber1)
        }
        #expect(fixture.graph.connections.count == 1)
    }

    @Test("Connecting a wire that replaces another on the inlet")
    func connectReplacingAWire()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let third = NumberBinaryOperator(context: context)
        step(fixture.undoManager) { fixture.graph.addNode(third) }
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: fixture.downstream.inputNumber1) }

        expectNamed("Connect Ports", fixture.undoManager) {
            fixture.graph.connect(third.outputNumber, to: fixture.downstream.inputNumber1)
        }
        #expect(fixture.graph.connections.map(\.outletPortID) == [third.outputNumber.id])
    }

    @Test("Disconnecting a wire")
    func disconnect()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: fixture.downstream.inputNumber1) }

        expectNamed("Disconnect Ports", fixture.undoManager) {
            fixture.graph.disconnect(fixture.upstream.outputNumber, from: fixture.downstream.inputNumber1)
        }
        #expect(fixture.graph.connections.isEmpty)
    }

    @Test("Disconnecting every wire on a port with two")
    func disconnectAll()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        step(fixture.undoManager) {
            fixture.graph.connect(fixture.upstream.outputNumber, to: fixture.downstream.inputNumber1)
            fixture.graph.connect(fixture.upstream.outputNumber, to: fixture.downstream.inputNumber2)
        }

        expectNamed("Disconnect Ports", fixture.undoManager) {
            fixture.graph.disconnectAll(from: fixture.upstream.outputNumber)
        }
        #expect(fixture.graph.connections.isEmpty)
    }

    @Test("Disabling and enabling a wire")
    func disableAndEnable() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        var connection: Connection?
        step(fixture.undoManager) { connection = fixture.graph.connect(fixture.upstream.outputNumber, to: fixture.downstream.inputNumber1) }
        let wire = try #require(connection)

        expectNamed("Disable Connection", fixture.undoManager) {
            fixture.graph.setConnection(wire, active: false)
        }
        let disabled = try #require(fixture.graph.connections.first)
        #expect(!disabled.active)

        expectNamed("Enable Connection", fixture.undoManager) {
            fixture.graph.setConnection(disabled, active: true)
        }
        #expect(fixture.graph.connections.first?.active == true)
    }

    @Test("Deleting a wired node")
    func deleteWiredNode()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let third = NumberBinaryOperator(context: context)
        step(fixture.undoManager) {
            fixture.graph.addNode(third)
            fixture.graph.connect(fixture.upstream.outputNumber, to: fixture.downstream.inputNumber1)
            fixture.graph.connect(fixture.downstream.outputNumber, to: third.inputNumber1)
        }

        expectNamed("Delete Node", fixture.undoManager) {
            fixture.graph.delete(node: fixture.downstream)
        }
        #expect(fixture.graph.connections.isEmpty)
    }

    @Test("Duplicating wired nodes")
    func duplicateNodes()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: fixture.downstream.inputNumber1) }

        expectNamed("Duplicate Nodes", fixture.undoManager) {
            _ = fixture.graph.duplicateNodes([fixture.upstream, fixture.downstream])
        }
        #expect(fixture.graph.nodes.count == 4)
        #expect(fixture.graph.connections.count == 2)
    }
}
