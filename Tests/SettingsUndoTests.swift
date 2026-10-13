import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// A node's settings change through Graph.setSettings as one undo step,
/// which puts back the ports the change touched; the wires and proxies those
/// ports take register steps of their own in the same group. A settings view
/// edits a draft and commits it.
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

    private func expression(_ text: String) -> MathExpressionSettings
    {
        MathExpressionSettings(stringExpression: text)
    }

    private func isWired(_ fixture: Fixture, to inletID: UUID) -> Bool
    {
        let outletID = fixture.upstream.outputNumber.id
        return fixture.graph.connections.contains { $0.inletPortID == inletID && $0.outletPortID == outletID }
    }

    // MARK: - Steps

    @Test("A settings change is one undo step, taking back the ports and wires it removed")
    func settingsChangeIsOneStep() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let y = try #require(inlet("y", of: node))
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: y) }

        fixture.graph.setSettings(expression("x"), on: node)
        #expect(fixture.undoManager.undoActionName == "Change Settings")
        #expect(inlet("y", of: node) == nil)
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        #expect(node.stringExpression == "x + y")
        #expect(inlet("y", of: node)?.id == y.id)
        #expect(isWired(fixture, to: y.id))

        fixture.undoManager.redo()
        #expect(node.stringExpression == "x")
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        fixture.undoManager.undo()
        #expect(fixture.graph.connections.isEmpty)
        #expect(node.stringExpression == "x + y")
    }

    @Test("A value equal to the node's settings records nothing")
    func equalValueRecordsNothing()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        fixture.undoManager.removeAllActions()

        fixture.graph.setSettings(expression("x + y"), on: node)
        #expect(!fixture.undoManager.canUndo)
    }

    @Test("Graph.undo while a draft waits for its pause first commits it, and undoes that")
    func undoWhileEditingCommitsTheDraftFirst()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }

        let model = MathExpressionNode.SettingsModel(node: node)
        model.stringExpression = "x * y"
        #expect(node.stringExpression == "x + y", "the node is not written until the draft is committed")

        fixture.graph.undo()
        #expect(node.stringExpression == "x + y")
        #expect(fixture.graph.nodes.contains { $0 === node })
        #expect(model.stringExpression == "x + y")

        fixture.graph.redo()
        #expect(node.stringExpression == "x * y")
        #expect(model.stringExpression == "x * y")

        fixture.graph.undo()
        fixture.graph.undo()
        #expect(!fixture.graph.nodes.contains { $0 === node })
    }

    @Test("A strategy change records once, out of a settings view or in one, and undo takes back the wire it dropped")
    func strategyChangeIsOneStep() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = SampleAndHoldNode(context: context, initialStrategy: PortType.Float.rawValue)
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let value = try #require(node.findPort(named: "inputValue") as Fabric.Port?)
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: value) }

        step(fixture.undoManager) { node.setStrategy(PortType.Geometry.rawValue) }
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        #expect(node.strategy == PortType.Float.rawValue)
        #expect((node.findPort(named: "inputValue") as Fabric.Port?)?.id == value.id)
        #expect(fixture.graph.connections.count == 1)

        // The picker: one choice, one step.
        let picker = node.strategySettingsModel
        #expect(picker.strategy == PortType.Float.rawValue, "the picker follows undo")
        picker.strategy = PortType.Geometry.rawValue
        #expect(node.strategy == PortType.Geometry.rawValue)
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        #expect(node.strategy == PortType.Float.rawValue)
        #expect(picker.strategy == PortType.Float.rawValue)
        #expect(fixture.graph.connections.count == 1)

        fixture.undoManager.undo()
        #expect(fixture.graph.connections.isEmpty)
        #expect(node.strategy == PortType.Float.rawValue)

        fixture.undoManager.redo()
        fixture.undoManager.redo()
        #expect(node.strategy == PortType.Geometry.rawValue)
        #expect(fixture.graph.connections.isEmpty)
    }

    @Test("A route count and type changed in one commit are one step, and undo brings back the routes with their ids and wires")
    func routingChangeIsOneStep() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = SwitchNode(context: context, routeCount: 4, portType: .Float)
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let fourth = try #require(node.findPort(named: "input3") as Fabric.Port?)
        let first = try #require(node.findPort(named: "input0") as Fabric.Port?)
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: fourth) }

        fixture.graph.setSettings(RoutingSettings(portType: .Int, routeCount: 2), on: node)
        #expect(node.findPort(named: "input3") as Fabric.Port? == nil)
        #expect((node.findPort(named: "input0") as Fabric.Port?)?.portType == .Int)
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        #expect(node.routeCount == 4)
        #expect(node.strategy == PortType.Float.rawValue)
        #expect((node.findPort(named: "input3") as Fabric.Port?)?.id == fourth.id)
        #expect((node.findPort(named: "input0") as Fabric.Port?)?.id == first.id)
        #expect(isWired(fixture, to: fourth.id))

        fixture.undoManager.redo()
        #expect(node.routeCount == 2)
        #expect(node.strategy == PortType.Int.rawValue)
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

        subgraph.subGraph.setSettings(expression("y"), on: node)
        #expect(!subgraph.ports.contains { $0.id == x.id })
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        let restored = try #require(subgraph.ports.first { $0.id == x.id })
        #expect(inlet("x", of: node)?.published == true)
        #expect(fixture.graph.connections.count == 1)
        #expect(fixture.upstream.outputNumber.connections.first?.inletPort === restored)

        fixture.undoManager.redo()
        #expect(fixture.graph.connections.isEmpty)
        #expect(!subgraph.ports.contains { $0.id == x.id })
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

        inner.subGraph.setSettings(expression("y"), on: node)
        #expect(!outer.ports.contains { $0.id == x.id })
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        let restoredMiddle = try #require(inner.ports.first { $0.id == x.id })
        #expect(restoredMiddle.published)
        #expect(restoredMiddle.publishedName == "Gain")
        let restoredTop = try #require(outer.ports.first { $0.id == x.id })
        #expect(fixture.upstream.outputNumber.connections.first?.inletPort === restoredTop)
    }

    @Test("A wire edited while a draft is open stays as edited when the settings change is undone")
    func wireEditedWhileOpenSurvivesTheSettingsUndo() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let x = try #require(inlet("x", of: node))
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: x) }

        let model = MathExpressionNode.SettingsModel(node: node)
        step(fixture.undoManager) { fixture.graph.disconnectAll(from: x) }
        model.stringExpression = "x * y"
        model.draft.commit()

        fixture.undoManager.undo()
        #expect(node.stringExpression == "x + y")
        #expect(fixture.graph.connections.isEmpty, "the settings step does not hold wires")

        fixture.undoManager.undo()
        #expect(isWired(fixture, to: x.id))
    }

    @Test("A draft committed as its view goes is a step; one still waiting through another edit is committed, and undone, by the next undo")
    func draftCommittedAsTheViewGoesIsAStep() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }

        let model = MathExpressionNode.SettingsModel(node: node)
        model.stringExpression = "x - y"
        model.draft.commit()
        model.stringExpression = "x * y"
        step(fixture.undoManager) {
            fixture.graph.registerOffsetChange(of: fixture.upstream, from: fixture.upstream.offset)
            fixture.upstream.offset = CGSize(width: 10, height: 0)
        }
        #expect(node.stringExpression == "x - y", "another edit does not commit a waiting draft")

        fixture.graph.undo()
        #expect(node.stringExpression == "x - y")
        #expect(fixture.upstream.offset == CGSize(width: 10, height: 0))
        fixture.graph.undo()
        #expect(fixture.upstream.offset == .zero)
        fixture.graph.undo()
        #expect(node.stringExpression == "x + y")
        #expect(fixture.graph.nodes.contains { $0 === node })
    }

    @Test("Deleting a node with a draft not yet committed: undo brings it back as at its last commit")
    func uncommittedDraftOnADeletedNodeIsDropped()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let model = MathExpressionNode.SettingsModel(node: node)

        // Typed inside an edit already under way, the draft meets no
        // checkpoint before the delete; committed as the view goes, it is
        // dropped.
        step(fixture.undoManager) {
            model.stringExpression = "x"
            fixture.graph.delete(node: node)
            model.draft.commit()
        }
        #expect(fixture.graph.node(forID: node.id) == nil)
        #expect(model.stringExpression == "x + y")

        fixture.undoManager.undo()
        #expect(fixture.graph.node(forID: node.id) === node)
        #expect(node.stringExpression == "x + y")
        #expect(inlet("y", of: node) != nil)

        fixture.undoManager.redo()
        #expect(fixture.graph.node(forID: node.id) == nil)
        fixture.undoManager.undo()
        #expect(node.stringExpression == "x + y")
    }

    @Test("A draft still waiting when its node is deleted is dropped as the undo of the delete runs")
    func waitingDraftOnADeletedNodeIsDroppedAtUndo()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let model = MathExpressionNode.SettingsModel(node: node)

        model.stringExpression = "x"
        step(fixture.undoManager) { fixture.graph.delete(node: node) }
        #expect(fixture.graph.node(forID: node.id) == nil)

        fixture.graph.undo()
        #expect(fixture.graph.node(forID: node.id) === node)
        #expect(node.stringExpression == "x + y")
        #expect(inlet("y", of: node) != nil)
        #expect(model.stringExpression == "x + y")
    }

    @Test("Reading canRedo, or a plain checkpoint, does not commit a waiting draft")
    func checkpointDoesNotCommitAWaitingDraft()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let model = MathExpressionNode.SettingsModel(node: node)

        model.stringExpression = "x * "
        _ = fixture.undoManager.canRedo
        _ = fixture.graph.canRedo
        NotificationCenter.default.post(name: .NSUndoManagerCheckpoint, object: fixture.undoManager)
        #expect(node.stringExpression == "x + y")
        #expect(fixture.undoManager.undoActionName != "Change Settings")
        #expect(model.stringExpression == "x * ")
    }

    @Test("Graph.undo with the editor's event group open commits a waiting draft and undoes it; redo brings it back")
    func undoWithAnOpenEventGroupCommitsTheDraftFirst()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let model = MathExpressionNode.SettingsModel(node: node)

        step(fixture.undoManager) {
            fixture.graph.registerOffsetChange(of: fixture.upstream, from: fixture.upstream.offset)
            fixture.upstream.offset = CGSize(width: 10, height: 0)
        }
        fixture.undoManager.groupsByEvent = true
        // A registration between events opens the event's group, which the
        // run loop would close.
        fixture.graph.registerOffsetChange(of: fixture.upstream, from: fixture.upstream.offset)
        fixture.upstream.offset = CGSize(width: 20, height: 0)
        #expect(fixture.undoManager.groupingLevel == 1)
        model.stringExpression = "x * y"

        fixture.graph.undo()
        #expect(node.stringExpression == "x + y")
        #expect(model.stringExpression == "x + y")
        #expect(fixture.upstream.offset == CGSize(width: 10, height: 0))
        #expect(fixture.graph.nodes.contains { $0 === node })

        fixture.graph.redo()
        #expect(node.stringExpression == "x * y")
        #expect(model.stringExpression == "x * y")
        #expect(fixture.upstream.offset == CGSize(width: 20, height: 0))
    }

    @Test("A wire that specialises a numeric node is one undo step with the specialisation, as the editor's event groups have it")
    func specialisingWireIsOneStep() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = DistanceNode(context: context)
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        #expect(node.selectedNumericPortType == .NumericVirtual)
        let inlet = try #require(node.findPort(named: "inputA") as Fabric.Port?)

        // The event's group opens with the edit and stays open until the run
        // loop turns; undo closes it first.
        fixture.undoManager.groupsByEvent = true
        fixture.graph.connect(fixture.upstream.outputNumber, to: inlet)
        #expect(node.strategy == PortType.Float.rawValue)
        #expect(isWired(fixture, to: inlet.id))

        fixture.undoManager.undo()
        #expect(fixture.graph.connections.isEmpty)
        #expect(node.selectedNumericPortType == .NumericVirtual)
        #expect((node.findPort(named: "inputA") as Fabric.Port?)?.id == inlet.id)

        fixture.undoManager.redo()
        #expect(node.strategy == PortType.Float.rawValue)
        #expect(isWired(fixture, to: inlet.id))
        #expect(node.graph === fixture.graph)
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

        node.setStrategy(PortType.Geometry.rawValue)
        #expect(fixture.undoManager.undoActionName == "Change Settings")

        fixture.undoManager.undo()
        #expect(node.strategy == PortType.Float.rawValue)
        fixture.undoManager.redo()
        #expect(node.strategy == PortType.Geometry.rawValue)
    }

    @Test("A format string typed in the settings view is one step when it commits")
    func formatStringIsOneStep()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = StringFormatterNode(context: context, formatString: "{a}")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let portCount = node.ports.count

        let draft = NodeSettingsDraft(of: FormatStringSettings(formatString: node.formatString), on: node, commit: .afterPause)
        draft.value.formatString = "{a} {b}"
        draft.value.formatString = "{a} {b} {c}"
        #expect(node.ports.count == portCount)
        draft.commit()
        #expect(node.ports.count == portCount + 2)

        fixture.undoManager.undo()
        #expect(node.formatString == "{a}")
        #expect(node.ports.count == portCount)
        #expect(draft.value.formatString == "{a}")
    }

    // MARK: - Live code

    @Test("Encoding a Live Image node writes the source held and records nothing; taking the disk is an undo step an open editor follows")
    func liveImageTakesTheDiskOnlyWhenAsked() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = LiveImageNode(context: context)
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        guard let fileURL = node.shaderFileURL else { return }
        let held = node.shaderSource
        let editor = LiveImageNodeEditorModel(node: node)
        editor.content = held + "\n// typed in the editor\n"
        fixture.undoManager.removeAllActions()

        let edited = held + "\n// edited on disk\n"
        try edited.write(to: fileURL, atomically: false, encoding: .utf8)
        #expect((node.settings as? LiveImageSettings)?.shaderSource == held)

        // A copy, a duplicate or an export encodes the node.
        let data = try JSONEncoder().encode(node)
        let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(saved?["shaderSource"] as? String == held)
        #expect(node.shaderSource == held)
        #expect(!fixture.undoManager.canUndo)

        #expect(node.takeShaderSourceFromDisk())
        #expect(node.shaderSource == edited)
        #expect(editor.content == edited, "the editor's draft yields to the source taken")
        #expect(fixture.undoManager.undoActionName == "Change Settings")
        #expect(!node.takeShaderSourceFromDisk(), "the disk and the node agree")

        fixture.undoManager.undo()
        #expect(node.shaderSource == held)
        #expect(editor.content == held)
    }

    @Test("A Live Image editor opening takes the shader on disk as an edit")
    func liveImageEditorTakesTheDiskAsItOpens() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = LiveImageNode(context: context)
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        guard let fileURL = node.shaderFileURL else { return }
        let edited = node.shaderSource + "\n// edited on disk\n"
        try edited.write(to: fileURL, atomically: false, encoding: .utf8)

        let editor = LiveImageNodeEditorModel(node: node)
        #expect(editor.content == edited)
        #expect(node.shaderSource == edited)
        #expect(fixture.undoManager.undoActionName == "Change Settings")
    }

    @Test("Taking shaders from disk reaches Live Image nodes in sub graphs")
    func graphTakesShadersFromDiskThroughSubGraphs() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let subgraph = SubgraphNode(context: context)
        let node = LiveImageNode(context: context)
        step(fixture.undoManager) {
            fixture.graph.addNode(subgraph)
            subgraph.subGraph.addNode(node)
        }
        guard let fileURL = node.shaderFileURL else { return }
        let edited = node.shaderSource + "\n// edited on disk\n"
        try edited.write(to: fileURL, atomically: false, encoding: .utf8)

        fixture.graph.takeShaderSourcesFromDisk()
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

        fixture.graph.setSettings(JavaScriptSettings(scriptSource: """
        function main(value: Number  {
            return { doubled: value * 2 }
        }
        """), on: node)
        #expect(node.ports.map(\.id) == portIDs, "a script that does not parse leaves the ports where they are")

        fixture.undoManager.undo()
        #expect(node.ports.map(\.id) == portIDs)
        fixture.undoManager.redo()
        #expect(node.ports.map(\.id) == portIDs)
        #expect(Set(node.ports.map(\.id)).count == node.ports.count)
    }

    @Test("A code editor's draft is not written over a script undo puts back underneath it")
    func editorDraftLeavesARestoredScript() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = JavaScriptNode(context: context)
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let original = node.scriptSource
        let model = JavaScriptNodeEditorModel(node: node)
        model.content = original + "\n// edited"
        model.flush()
        #expect(node.scriptSource == original + "\n// edited")

        // The editor writes what it holds as it goes away.
        fixture.undoManager.undo()
        #expect(model.content == original)
        model.flush()
        #expect(node.scriptSource == original)
        #expect(fixture.undoManager.canRedo)
    }

    // MARK: - Every node

    /// Every registered node type that has settings, made fresh.
    private func nodesWithSettings(context: Context) throws -> [(name: String, node: Node)]
    {
        try NodeRegistry.shared.availableNodes.compactMap { wrapper in
            guard let node = try? wrapper.initializeNode(context: context), node.settings != nil else { return nil }
            return (wrapper.nodeClass.name, node)
        }
    }

    @Test("Every core node type applies its own settings and gives them back unchanged, ports and all")
    func everyNodeTypeRoundTripsItsOwnSettings() throws
    {
        guard let context = makeContext() else { return }
        var failures: [String] = []
        let nodes = try nodesWithSettings(context: context)
        #expect(!nodes.isEmpty)
        for (name, node) in nodes
        {
            guard let settings = node.settings else { continue }
            let portIDs = node.ports.map(\.id)
            node.apply(settings)
            if node.settings.map({ !$0.isEqual(to: settings) }) ?? true { failures.append("\(name): settings changed") }
            if node.ports.map(\.id) != portIDs { failures.append("\(name): ports changed") }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test("Every core node type saves its settings flattened into its own container and opens them as they were")
    func everyNodeTypeSavesItsSettingsFlattened() throws
    {
        guard let context = makeContext() else { return }
        var failures: [String] = []
        for (name, node) in try nodesWithSettings(context: context)
        {
            guard let settings = node.settings else { continue }
            let nodeJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(node)) as? NSDictionary
            let settingsJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AnyNodeSettings(settings))) as? NSDictionary
            for (key, value) in settingsJSON ?? [:] where nodeJSON?[key].map({ !($0 as AnyObject).isEqual(value) }) ?? true
            {
                failures.append("\(name): \(key) is not saved as the settings write it")
            }

            let graph = Graph(context: context)
            graph.addNode(node)
            let decoder = JSONDecoder()
            decoder.context = DecoderContext(documentContext: context)
            let decoded = try decoder.decode(Graph.self, from: JSONEncoder().encode(graph))
            if decoded.node(forID: node.id)?.settings.map({ !$0.isEqual(to: settings) }) ?? true
            {
                failures.append("\(name): settings do not open as they were saved")
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    /// Encodes an existential settings value on its own.
    private struct AnyNodeSettings: Encodable
    {
        let settings: any NodeSettings
        init(_ settings: any NodeSettings) { self.settings = settings }
        func encode(to encoder: Encoder) throws { try settings.encode(to: encoder) }
    }

    @Test("A node with a settings view gives its settings as a value")
    func settingsViewsHaveSettings() throws
    {
        guard let context = makeContext() else { return }
        // Their settings views edit inlets, or show what the node computes.
        let editsNoSettings: Set<String> = [
            AudioSpectrumNode.name,
            NumberTriggerNode.name,
            VisualizeNode.name,
            SyphonClientNode.name,
        ]
        var failures: [String] = []
        for wrapper in try NodeRegistry.shared.availableNodes
        {
            guard let node = try? wrapper.initializeNode(context: context),
                  node.providesSettingsView(),
                  node.settings == nil,
                  !editsNoSettings.contains(wrapper.nodeClass.name)
            else { continue }
            failures.append(wrapper.nodeClass.name)
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // MARK: - Review findings

    @Test("P1.1: x + y, then x, then x + y + 1, each committed; undo twice puts back y's own id and wire")
    func editAwayAndBackKeepsTheOriginalPortOnUndo() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let y = try #require(inlet("y", of: node))
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: y) }

        fixture.graph.setSettings(expression("x"), on: node)
        fixture.graph.setSettings(expression("x + y + 1"), on: node)
        let newY = try #require(inlet("y", of: node))
        #expect(newY.id != y.id)
        #expect(fixture.graph.connections.isEmpty)

        fixture.undoManager.undo()
        #expect(node.stringExpression == "x")
        #expect(inlet("y", of: node) == nil)

        fixture.undoManager.undo()
        #expect(node.stringExpression == "x + y")
        #expect(inlet("y", of: node)?.id == y.id)
        #expect(isWired(fixture, to: y.id))

        // Redo brings back the port the second commit made, under its own id.
        fixture.undoManager.redo()
        fixture.undoManager.redo()
        #expect(inlet("y", of: node)?.id == newY.id)
    }

    @Test("P1.2: a draft that goes away and returns to where it started commits nothing and loses nothing")
    func draftReturningToItsStartCommitsNothing() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let y = try #require(inlet("y", of: node))
        step(fixture.undoManager) { fixture.graph.connect(fixture.upstream.outputNumber, to: y) }
        fixture.undoManager.removeAllActions()

        let model = MathExpressionNode.SettingsModel(node: node)
        model.stringExpression = "x"
        model.stringExpression = "x + "
        model.stringExpression = "x + y"
        model.draft.commit()

        #expect(!fixture.undoManager.canUndo)
        #expect(inlet("y", of: node)?.id == y.id)
        #expect(isWired(fixture, to: y.id))
    }

    @Test("P2.1: a route count and then a type, each committed from the settings view, are two steps")
    func routeCountThenTypeAreTwoSteps() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = SwitchNode(context: context, routeCount: 4, portType: .Float)
        step(fixture.undoManager) { fixture.graph.addNode(node) }

        let draft = NodeSettingsDraft(of: RoutingSettings(strategy: node.strategy, routeCount: node.routeCount), on: node, commit: .eachChange)
        draft.value.routeCount = 2
        draft.value.strategy = PortType.Int.rawValue
        #expect(node.routeCount == 2)
        #expect(node.strategy == PortType.Int.rawValue)

        fixture.undoManager.undo()
        #expect(node.routeCount == 2)
        #expect(node.strategy == PortType.Float.rawValue)
        #expect(draft.value == RoutingSettings(portType: .Float, routeCount: 2))

        fixture.undoManager.undo()
        #expect(node.routeCount == 4)
        #expect(node.strategy == PortType.Float.rawValue)
        #expect(fixture.graph.nodes.contains { $0 === node })
    }

    @Test("P2.2: a parameter change waiting for its pause is committed before Graph.undo runs")
    func pendingParameterCommitComesBeforeUndo() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = NumberBinaryOperator(context: context)
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        let parameter = try #require(node.inputNumber1.parameter as? FloatParameter)
        parameter.value = 1
        let model = ParameterObservableModel(label: parameter.label,
                                             get: { parameter.value },
                                             set: { parameter.value = $0 },
                                             publisher: parameter.valuePublisher,
                                             graph: fixture.graph,
                                             undoParameter: parameter,
                                             commit: .afterPause)

        model.uiValue = 2
        #expect(!fixture.undoManager.undoActionName.hasPrefix("Change"), "not committed before its pause")

        fixture.graph.undo()
        #expect(parameter.value == 1)
        #expect(fixture.graph.nodes.contains { $0 === node })

        fixture.graph.redo()
        #expect(parameter.value == 2)
    }

    @Test("P2.3: a Switch index clamped by a smaller route count comes back on undo")
    func clampedIndexComesBackOnUndo() throws
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = SwitchNode(context: context, routeCount: 4, portType: .Float)
        step(fixture.undoManager) { fixture.graph.addNode(node) }
        node.inputIndex.value = 3

        fixture.graph.setSettings(RoutingSettings(portType: .Float, routeCount: 2), on: node)
        #expect(node.inputIndex.value == 1)

        fixture.undoManager.undo()
        #expect(node.routeCount == 4)
        #expect(node.inputIndex.value == 3)

        fixture.undoManager.redo()
        #expect(node.inputIndex.value == 1)
    }

    @Test("P2.4: a settings change made under an open editor replaces its draft")
    func settingsChangeUnderAnEditorReplacesItsDraft()
    {
        guard let context = makeContext() else { return }
        let fixture = makeFixture(context: context)
        let node = MathExpressionNode(context: context, expression: "x + y")
        step(fixture.undoManager) { fixture.graph.addNode(node) }

        let model = MathExpressionNode.SettingsModel(node: node)
        model.stringExpression = "x * y"
        fixture.graph.setSettings(expression("x - y"), on: node)
        #expect(model.stringExpression == "x - y")

        // The draft it replaced is not committed later.
        model.draft.commit()
        #expect(node.stringExpression == "x - y")
        fixture.undoManager.undo()
        #expect(node.stringExpression == "x + y")
        #expect(model.stringExpression == "x + y")
    }

    // MARK: - Saving

    @Test("Settings a node writes are saved and opened as before")
    func settingsStillSave() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        graph.addNode(MathExpressionNode(context: context, expression: "x * 2"))
        graph.addNode(SampleAndHoldNode(context: context, initialStrategy: PortType.String.rawValue))
        graph.addNode(SwitchNode(context: context, routeCount: 5, portType: .Int))

        let data = try JSONEncoder().encode(graph)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(Graph.self, from: data)
        #expect(decoded.nodes.compactMap { $0 as? MathExpressionNode }.first?.stringExpression == "x * 2")
        #expect(decoded.nodes.compactMap { $0 as? SampleAndHoldNode }.first?.strategy == PortType.String.rawValue)
        let routing = decoded.nodes.compactMap { $0 as? SwitchNode }.first
        #expect(routing?.routeCount == 5)
        #expect(routing?.strategy == PortType.Int.rawValue)

        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"stringExpression\""))
        #expect(json.contains("\"routeCount\""))
        #expect(json.contains("\"strategy\""))
    }
}
