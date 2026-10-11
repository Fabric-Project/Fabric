import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// A node's settings, edited in its settings view or changed by the node
/// itself, are undone and redone with the ports and wires they decide.
@Suite("Settings Undo")
@MainActor
struct SettingsUndoTests
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

    private struct Fixture
    {
        let graph: Graph
        let upstream: NumberBinaryOperator
        let undoManager: UndoManager
    }

    private func makeFixture(context: Context) -> Fixture
    {
        let graph = Graph(context: context)
        let upstream = NumberBinaryOperator(context: context)
        graph.addNode(upstream)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        graph.undoManager = undoManager
        return Fixture(graph: graph, upstream: upstream, undoManager: undoManager)
    }

    /// One edit per group, as the editor's event loop makes them.
    private func step(_ undoManager: UndoManager, _ edit: () -> Void)
    {
        undoManager.beginUndoGrouping()
        edit()
        undoManager.endUndoGrouping()
    }

    private func inlet(_ name: String, of node: Node) -> Fabric.Port?
    {
        node.inputPorts().first { $0.name == name }
    }

    @Test("Editing settings in the settings view is one undo step, taking back the ports and wires they removed")
    func sessionIsOneStep() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let y = try #require(inlet("y", of: node))
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: y) }

        let session = NodeSettingsSession(node: node)
        node.stringExpression = "x + "
        node.stringExpression = "x"
        session.end()

        #expect(inlet("y", of: node) == nil)
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        #expect(node.stringExpression == "x + y")
        let restored = try #require(inlet("y", of: node))
        #expect(restored.id == y.id)
        let outletID = fixture.upstream.outputNumber.id
        let rewired = fixture.graph.connections.contains { $0.inletPortID == y.id && $0.outletPortID == outletID }
        #expect(rewired)

        fixture.undoManager.redo()
        #expect(node.stringExpression == "x")
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        fixture.undoManager.undo()
        #expect(fixture.graph.connections.isEmpty)
        #expect(node.stringExpression == "x + y")
    }

    @Test("Undo while the settings view is open first takes back what it has edited so far")
    func undoWhileOpenTakesBackTheEditFirst()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }

        let session = NodeSettingsSession(node: node)
        node.stringExpression = "x * y"

        fixture.undoManager.undo()
        #expect(node.stringExpression == "x + y")
        #expect(fixture.graph.nodes.contains { $0 === node })

        fixture.undoManager.redo()
        #expect(node.stringExpression == "x * y")

        // What undo and redo put back is not an edit of the view's.
        session.end()
        fixture.undoManager.undo()
        #expect(node.stringExpression == "x + y")
        #expect(fixture.graph.nodes.contains { $0 === node })
    }

    @Test("A settings view closed with nothing changed records nothing")
    func unchangedSessionRecordsNothing()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        fixture.undoManager.removeAllActions()

        let session = NodeSettingsSession(node: node)
        node.stringExpression = "x"
        node.stringExpression = "x + y"
        session.end()
        #expect(!fixture.undoManager.canUndo)
    }

    @Test("A strategy change records itself once, in the settings view or out of it, and undo takes back the wire it dropped")
    func strategyChangeIsOneStep() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = SampleAndHoldNode(context: context, initialStrategy: PortType.Float.rawValue)
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let value = try #require(node.findPort(named: "inputValue") as Fabric.Port?)
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: value) }

        let session = NodeSettingsSession(node: node)
        step(fixture.undoManager) { node.strategy = PortType.Geometry.rawValue }
        session.end()
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        #expect(node.strategy == PortType.Float.rawValue)
        #expect((node.findPort(named: "inputValue") as Fabric.Port?)?.id == value.id)
        #expect(fixture.graph.connections.count == 1)

        fixture.undoManager.undo()
        #expect(fixture.graph.connections.isEmpty)
        #expect(node.strategy == PortType.Float.rawValue)

        fixture.undoManager.redo()
        fixture.undoManager.redo()
        #expect(node.strategy == PortType.Geometry.rawValue)
        #expect(fixture.graph.connections.isEmpty)
    }

    @Test("A route count and type changed in one pass are one step, and undo brings back the routes with their ids and wires")
    func routingChangeIsOneStep() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = SwitchNode(context: context, routeCount: 4, portType: .Float)
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let fourth = try #require(node.findPort(named: "input3") as Fabric.Port?)
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: fourth) }

        let session = NodeSettingsSession(node: node)
        node.setRouteCount(2)
        session.end()
        #expect(node.findPort(named: "input3") as Fabric.Port? == nil)
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        #expect(node.routeCount == 4)
        #expect((node.findPort(named: "input3") as Fabric.Port?)?.id == fourth.id)
        #expect(fixture.graph.connections.count == 1)

        fixture.undoManager.redo()
        #expect(node.routeCount == 2)
        #expect(fixture.graph.connections.isEmpty)
    }

    @Test("Undo brings back a published port a settings change removed, with the wire onto its proxy in the graph around")
    func undoRestoresTheWireOntoAProxy() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let subgraph = SubgraphNode(context: context)
        let node = MathExpressionNode(context: context, expression: "x")
        step(fixture.undoManager) {
            fixture.graph.addNode(subgraph)
            subgraph.subGraph.undoManager = fixture.undoManager
            subgraph.subGraph.addNode(node)
        }
        let x = try #require(inlet("x", of: node))
        step(fixture.undoManager) { subgraph.subGraph.setPublished(true, on: x) }
        let proxy = try #require(subgraph.ports.first { $0.id == x.id })
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: proxy) }

        let session = NodeSettingsSession(node: node)
        node.stringExpression = "y"
        session.end()
        #expect(!subgraph.ports.contains { $0.id == x.id })
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        let restored = try #require(subgraph.ports.first { $0.id == x.id })
        let outletID = fixture.upstream.outputNumber.id
        #expect(fixture.graph.connections.count == 1)
        #expect(fixture.upstream.outputNumber.connections.first?.inletPort === restored)
        #expect(fixture.graph.connections.first?.outletPortID == outletID)

        fixture.undoManager.redo()
        #expect(fixture.graph.connections.isEmpty)
    }

    @Test("A format string typed in the settings view is one step")
    func formatStringIsOneStep()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = StringFormatterNode(context: context, formatString: "{a}")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let portCount = node.ports.count

        let session = NodeSettingsSession(node: node)
        node.setFormatString("{a} {b}")
        node.setFormatString("{a} {b} {c}")
        session.end()
        #expect(node.ports.count == portCount + 2)

        fixture.undoManager.undo()
        #expect(node.formatString == "{a}")
        #expect(node.ports.count == portCount)
    }

    @Test("Every core node type takes back its own settings unchanged, ports and all")
    func everyNodeTypeRestoresItsOwnSettings() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        var failures: [String] = []
        for wrapper in try NodeRegistry.shared.availableNodes
        {
            guard let node = try? wrapper.initializeNode(context: context), node.providesSettingsView() else { continue }
            step(fixture.undoManager) { fixture.graph.addNode(node) }
            guard let snapshot = node.settingsSnapshot() else { continue }
            let portIDs = node.ports.map(\.id)

            do { try node.restore(snapshot) }
            catch { failures.append("\(wrapper.nodeClass.name): \(error)"); continue }

            if node.settingsSnapshot()?.settings != snapshot.settings { failures.append("\(wrapper.nodeClass.name): settings changed") }
            if node.ports.map(\.id) != portIDs { failures.append("\(wrapper.nodeClass.name): ports changed") }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    /// Nodes whose settings view edits nothing the node encodes beyond its
    /// ports: what they encode besides is not a setting.
    private static let encodesNoSettings: Set<String> = [
        "StringSplitNode.swift",    // the custom separator is the Separator inlet's value
        "VisualizeNode.swift",      // its one inlet
    ]

    @Test("A node that writes settings puts them back, and one with a settings view and state of its own writes it as settings")
    func settingsAreWrittenAndPutBack() throws
    {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fabric", directoryHint: .isDirectory)
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let file as URL in files where file.pathExtension == "swift"
        {
            let source = try String(contentsOf: file, encoding: .utf8)
            let writes = source.contains("override func encodeSettings(")
            let restores = source.contains("override func restoreSettings(")
            if writes != restores { offenders.append("\(file.lastPathComponent): encodeSettings and restoreSettings come as a pair") }

            let hasSettingsView = source.contains("func settingsView(")
            let encodesState = source.contains("override func encode(to")
            if hasSettingsView, encodesState, !writes, !Self.encodesNoSettings.contains(file.lastPathComponent)
            {
                offenders.append("\(file.lastPathComponent): has a settings view and encodes state, but writes no settings")
            }
        }
        #expect(offenders.isEmpty, "\(offenders.joined(separator: "\n"))")
    }

    @Test("Settings a node writes are saved and opened as before")
    func settingsStillSave() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        graph.addNode(MathExpressionNode(context: context, expression: "x * 2"))
        graph.addNode(SampleAndHoldNode(context: context, initialStrategy: PortType.String.rawValue))

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(Graph.self, from: JSONEncoder().encode(graph))
        #expect(decoded.nodes.compactMap { $0 as? MathExpressionNode }.first?.stringExpression == "x * 2")
        #expect(decoded.nodes.compactMap { $0 as? SampleAndHoldNode }.first?.strategy == PortType.String.rawValue)
    }

    @Test("A wire edited while the settings view is open stays as edited when the settings change is undone")
    func wireEditedWhileOpenSurvivesTheSettingsUndo() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let x = try #require(inlet("x", of: node))
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: x) }

        let session = NodeSettingsSession(node: node)
        step(fixture.undoManager) { fixture.graph.disconnectAll(from: x) }
        node.stringExpression = "x * y"
        session.end()

        fixture.undoManager.undo()
        #expect(node.stringExpression == "x + y")
        #expect(fixture.graph.connections.isEmpty,
                "the wires the view's step started from are those there when the step was taken")

        fixture.undoManager.undo()
        #expect(fixture.graph.connections.filter { $0.inletPortID == x.id }.map(\.outletPortID) == [fixture.upstream.outputNumber.id])
    }

    @Test("Undo brings back a port published two levels up, with the wires and publishing at each level")
    func undoRestoresAPortPublishedTwoLevelsUp() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let outer = SubgraphNode(context: context)
        let inner = SubgraphNode(context: context)
        let node = MathExpressionNode(context: context, expression: "x")
        step(fixture.undoManager) {
            fixture.graph.addNode(outer)
            outer.subGraph.addNode(inner)
            inner.subGraph.addNode(node)
        }
        inner.subGraph.undoManager = fixture.undoManager
        let x = try #require(inlet("x", of: node))
        step(fixture.undoManager) { inner.subGraph.setPublished(true, on: x) }
        let middle = try #require(inner.ports.first { $0.id == x.id })
        step(fixture.undoManager) {
            outer.subGraph.setPublished(true, on: middle)
            outer.subGraph.setPublishedName("Gain", on: middle)
        }
        let top = try #require(outer.ports.first { $0.id == x.id })
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: top) }

        let session = NodeSettingsSession(node: node)
        node.stringExpression = "y"
        session.end()
        #expect(!outer.ports.contains { $0.id == x.id })
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        let restoredMiddle = try #require(inner.ports.first { $0.id == x.id })
        #expect(restoredMiddle.published)
        #expect(restoredMiddle.publishedName == "Gain")
        let restoredTop = try #require(outer.ports.first { $0.id == x.id })
        #expect(fixture.upstream.outputNumber.connections.first?.inletPort === restoredTop)
    }

    @Test("A change written as the settings view goes away is recorded before the next step")
    func changeWrittenAfterTheViewEndsIsRecorded() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }

        let session = NodeSettingsSession(node: node)
        node.stringExpression = "x - y"
        session.end()
        // A control in the view writing what it holds as it goes away.
        node.stringExpression = "x * y"
        step(fixture.undoManager) {
            fixture.graph.registerOffsetChange(of: fixture.upstream, from: fixture.upstream.offset)
            fixture.upstream.offset = CGSize(width: 10, height: 0)
        }

        fixture.undoManager.undo()
        fixture.undoManager.undo()
        #expect(node.stringExpression == "x - y")
        fixture.undoManager.undo()
        #expect(node.stringExpression == "x + y")
        #expect(fixture.graph.nodes.contains { $0 === node })
    }

    @Test("Deleting a node with its settings view open: undo brings it back as it was before the edit")
    func settingsEditedWhenDeletedComesBackUnedited() async throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        // The editor's event groups: an edit opens one with no checkpoint,
        // and the run loop closes it.
        let undoManager = UndoManager()
        graph.undoManager = undoManager
        let node = MathExpressionNode(context: context, expression: "x + y")
        graph.addNode(node)
        try await Task.sleep(for: .milliseconds(50))
        #expect(undoManager.groupingLevel == 0)

        let session = NodeSettingsSession(node: node)
        node.stringExpression = "x"
        graph.delete(node: node)
        #expect(undoManager.groupingLevel == 1, "the delete opened the event's group")
        try await Task.sleep(for: .milliseconds(50))
        session.end()
        #expect(undoManager.groupingLevel == 0)
        #expect(graph.node(forID: node.id) == nil)

        undoManager.undo()
        #expect(graph.node(forID: node.id) === node)
        #expect(node.stringExpression == "x + y")
        #expect(inlet("y", of: node) != nil)

        undoManager.redo()
        #expect(graph.node(forID: node.id) == nil)
        undoManager.undo()
        #expect(node.stringExpression == "x + y")
    }

    @Test("A strategy change in a sub graph the canvas has not entered records on the root's undo manager")
    func strategyChangeInAnUnenteredSubGraphIsAStep() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let container = SubgraphNode(context: context)
        let node = SampleAndHoldNode(context: context, initialStrategy: PortType.Float.rawValue)
        step(fixture.undoManager) {
            fixture.graph.addNode(container)
            container.subGraph.addNode(node)
        }
        #expect(container.subGraph.undoManager == nil)

        step(fixture.undoManager) { node.strategy = PortType.Geometry.rawValue }
        #expect(fixture.undoManager.undoActionName == "Change Settings")

        fixture.undoManager.undo()
        #expect(node.strategy == PortType.Float.rawValue)
        fixture.undoManager.redo()
        #expect(node.strategy == PortType.Geometry.rawValue)
    }

    @Test("A settings snapshot takes the shader source held, not what is on disk; a save takes the disk")
    func liveImageSnapshotLeavesTheDiskAlone() throws
    {
        guard let context = makeContext() else { return }
        let node = LiveImageNode(context: context)
        guard let fileURL = node.shaderFileURL else { return }
        let held = node.shaderSource
        let edited = held + "\n// edited on disk\n"
        try edited.write(to: fileURL, atomically: false, encoding: .utf8)

        _ = node.settingsSnapshot()
        #expect(node.shaderSource == held)

        _ = try JSONEncoder().encode(node)
        #expect(node.shaderSource == edited)
    }

    @Test("Undo and redo across a script that does not compile leave one of each port")
    func undoToAnUncompilableScriptKeepsOneOfEachPort() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = JavaScriptNode(context: context)
        node.updateScriptSource("""
        function main(value: Number): { doubled: Number }
        {
            return { doubled: value * 2 }
        }
        """)
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let portIDs = node.ports.map(\.id)

        let session = NodeSettingsSession(node: node)
        node.updateScriptSource("""
        function main(value: Number  {
            return { doubled: value * 2 }
        }
        """)
        session.end()
        #expect(node.ports.map(\.id) == portIDs, "a script that does not parse leaves the ports where they are")

        fixture.undoManager.undo()
        #expect(node.ports.map(\.id) == portIDs)
        fixture.undoManager.redo()
        #expect(node.ports.map(\.id) == portIDs)
        #expect(Set(node.ports.map(\.id)).count == node.ports.count)
    }

    @Test("A code editor's draft is not written over a script put back underneath it")
    func editorDraftLeavesARestoredScript() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context)
        let original = node.scriptSource
        let model = JavaScriptNodeEditorModel(node: node)
        model.content = original + "\n// edited"
        model.flush()
        #expect(node.scriptSource == original + "\n// edited")

        // Undo puts the script back; the view is rebuilt, and the old editor
        // writes what it holds as it goes away.
        node.updateScriptSource(original)
        model.flush()
        #expect(node.scriptSource == original)
    }
}
