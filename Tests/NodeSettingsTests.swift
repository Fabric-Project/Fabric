import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// A node's settings are one value it gives and applies, saved flattened into
/// its own container.
@Suite("Node Settings")
@MainActor
struct NodeSettingsTests
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
            for case let key as String in settingsJSON?.allKeys ?? [] where Node.CodingKeys(rawValue: key) != nil
            {
                failures.append("\(name): \(key) is a key of Node")
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
        // Their settings views edit inlets, or show what the node computes
        // or its status.
        let editsNoSettings: Set<String> = [
            AudioSpectrumNode.name,
            CameraProviderNode.name,
            NumberTriggerNode.name,
            ScreenCaptureProviderNode.name,
            SyphonClientNode.name,
            VisualizeNode.name,
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

    // MARK: - Procedural construction

    @Test("init(context:settings:) builds the node that applying the same settings to a fresh one does")
    func settingsInitializersBuildThePorts() throws
    {
        guard let context = makeContext() else { return }
        let script = """
        function main(value: Number): { doubled: Number }
        {
            return { doubled: value * 2 }
        }
        """
        let element = HIDElementInfo(id: "axis-x", cookie: 1, usagePage: 1, usage: 0x30,
                                     displayName: "X", min: 0, max: 255, isRelative: false)
        let llm = LocalLLMSettings(selectedModelID: LocalLLMNode(context: context).selectedModelID, temperature: 0.3, updateIntervalSeconds: 0.25,
                                   systemPromptOverride: "", chatModeEnabled: true, desiredMaxContextTokens: 4_096)
        let vlm = LocalVLMSettings(selectedModelID: LocalVLMNode(context: context).selectedModelID, temperature: 0.3, updateIntervalSeconds: 0.25,
                                   systemPromptOverride: "", chatModeEnabled: true, desiredMaxContextTokens: 4_096)
        let timeline = TimelineSettings(duration: 2, tracks: [TimelineTrack(name: "A", duration: 2), TimelineTrack(name: "B", duration: 2)])
        let osc = OSCReceiveSettings(listenPort: 9100, addressBindings: [OSCAddressBinding(address: "/x", dataType: .float)])
        let midi = MIDIInputSettings(selectedInputID: nil, configuredInputs: [DetectedMIDIInput(type: .controlChange, channel: 0, number: 7)])
        let cases: [(name: String, built: Node, fresh: Node, settings: any NodeSettings)] = [
            ("Strategy",
             SampleAndHoldNode(context: context, settings: StrategyNodeSettings(strategy: PortType.String.rawValue)),
             SampleAndHoldNode(context: context),
             StrategyNodeSettings(strategy: PortType.String.rawValue)),
            ("Routing",
             SwitchNode(context: context, settings: RoutingSettings(portType: .Int, routeCount: 5)),
             SwitchNode(context: context),
             RoutingSettings(portType: .Int, routeCount: 5)),
            ("Routing, a type no longer offered",
             SwitchNode(context: context, settings: RoutingSettings(strategy: "Removed Type", routeCount: 3)),
             SwitchNode(context: context),
             RoutingSettings(strategy: "Removed Type", routeCount: 3)),
            ("Format String",
             StringFormatterNode(context: context, settings: FormatStringSettings(formatString: "{a} {b}")),
             StringFormatterNode(context: context),
             FormatStringSettings(formatString: "{a} {b}")),
            ("Math Expression",
             MathExpressionNode(context: context, settings: MathExpressionSettings(stringExpression: "a + b")),
             MathExpressionNode(context: context),
             MathExpressionSettings(stringExpression: "a + b")),
            ("Parametric Geometry",
             MathExpressionParametricGeometryNode(context: context, settings: ParametricExpressionSettings(expressionX: "a * u", expressionY: "v", expressionZ: "b")),
             MathExpressionParametricGeometryNode(context: context),
             ParametricExpressionSettings(expressionX: "a * u", expressionY: "v", expressionZ: "b")),
            ("JavaScript",
             JavaScriptNode(context: context, settings: JavaScriptSettings(scriptSource: script, selectedTimeMode: .TimeBase)),
             JavaScriptNode(context: context),
             JavaScriptSettings(scriptSource: script, selectedTimeMode: .TimeBase)),
            ("Timeline",
             TimelineNode(context: context, settings: timeline),
             TimelineNode(context: context),
             timeline),
            ("OSC Receive",
             OSCReceiveNode(context: context, settings: osc),
             OSCReceiveNode(context: context),
             osc),
            ("Keyboard",
             KeyboardNode(context: context, settings: KeyboardSettings(keyBindings: [KeyBinding(characters: "a", keyDescription: "a", modifiersDescription: "")])),
             KeyboardNode(context: context),
             KeyboardSettings(keyBindings: [KeyBinding(characters: "a", keyDescription: "a", modifiersDescription: "")])),
            ("MIDI Input",
             MIDIInputNode(context: context, settings: midi),
             MIDIInputNode(context: context),
             midi),
            ("HID",
             HIDNode(context: context, settings: HIDSettings(selectedDeviceID: "absent", deviceElements: [element])),
             HIDNode(context: context),
             HIDSettings(selectedDeviceID: "absent", deviceElements: [element])),
            ("Game Controller",
             GameControllerNode(context: context, settings: GameControllerSettings(selectedControllerID: nil, portDescriptors: [DeviceOutputPortDescriptor(name: "A", isButton: true)])),
             GameControllerNode(context: context),
             GameControllerSettings(selectedControllerID: nil, portDescriptors: [DeviceOutputPortDescriptor(name: "A", isButton: true)])),
            ("Deferred Subgraph",
             DeferredSubgraphNode(context: context, settings: DeferredSubgraphSettings(deferredMRTEnabled: true)),
             DeferredSubgraphNode(context: context),
             DeferredSubgraphSettings(deferredMRTEnabled: true)),
            ("Local LLM",
             LocalLLMNode(context: context, settings: llm),
             LocalLLMNode(context: context),
             llm),
            ("Local VLM",
             LocalVLMNode(context: context, settings: vlm),
             LocalVLMNode(context: context),
             vlm),
        ]

        func shape(_ node: Node) -> [String] { node.ports.map { "\($0.name): \($0.portType)" } }
        for (name, built, fresh, settings) in cases
        {
            let freshShape = shape(fresh)
            fresh.apply(settings)
            #expect(built.settings?.isEqual(to: settings) == true, "\(name): settings")
            #expect(fresh.settings?.isEqual(to: settings) == true, "\(name): applied settings")
            #expect(shape(built) == shape(fresh), "\(name): ports")
            // A local model's settings shape no ports.
            #expect(shape(built) != freshShape || built is LocalModelSettingsMirroring, "\(name): the settings shape the ports")
        }
    }

    // MARK: - Changing settings

    @Test("setSettings leaves a node holding the value, or given another node's settings type, as it is")
    func setSettingsIgnoresNoChange() throws
    {
        guard let context = makeContext() else { return }
        let node = SwitchNode(context: context, routeCount: 4, portType: .Float)
        let before = try #require(node.settings)
        let portIDs = node.ports.map(\.id)

        node.setSettings(before)
        node.setSettings(MathExpressionSettings(stringExpression: "x"))
        node.apply(MathExpressionSettings(stringExpression: "x"))
        #expect(node.settings?.isEqual(to: before) == true)
        #expect(node.ports.map(\.id) == portIDs)

        // A strategy carried by another node's settings type is not taken either.
        let sampleAndHold = SampleAndHoldNode(context: context, initialStrategy: PortType.Float.rawValue)
        sampleAndHold.apply(RoutingSettings(portType: .Int, routeCount: 3))
        #expect(sampleAndHold.strategy == PortType.Float.rawValue)

        node.setSettings(RoutingSettings(portType: .Float, routeCount: 2))
        #expect(node.routeCount == 2)
    }

    @Test("setStrategy and setRouteCount each change their part of a routing node's settings")
    func routingSettersChangeTheirPart() throws
    {
        guard let context = makeContext() else { return }
        let node = SwitchNode(context: context, routeCount: 4, portType: .Float)

        node.setStrategy(PortType.Int.rawValue)
        #expect(node.settings?.isEqual(to: RoutingSettings(portType: .Int, routeCount: 4)) == true)

        node.setRouteCount(3)
        #expect(node.settings?.isEqual(to: RoutingSettings(portType: .Int, routeCount: 3)) == true)
    }

    @Test("A track added after a removal takes a name not in use, so each track has a port")
    func timelineTrackAddedAfterARemovalIsNamedApart() throws
    {
        guard let context = makeContext() else { return }
        let node = TimelineNode(context: context)
        var settings = TimelineSettings(duration: 1, tracks: [])
        settings.addTrack()
        settings.addTrack()
        settings.addTrack()
        settings.removeTrack(id: settings.tracks[1].id)
        settings.addTrack()
        #expect(Set(settings.tracks.map(\.name)).count == 3)

        node.setSettings(settings)
        #expect(node.outputPorts().map(\.name) == settings.tracks.map(\.name))
    }

    @Test("A renamed track's port is replaced and every other track keeps its port")
    func timelineRenameKeepsTheOtherTracksPorts() throws
    {
        guard let context = makeContext() else { return }
        let node = TimelineNode(context: context, settings: TimelineSettings(duration: 1, tracks: [TimelineTrack(name: "A", duration: 1),
                                                                                                    TimelineTrack(name: "B", duration: 1)]))
        let portA = try #require(node.outputPorts().first { $0.name == "A" })
        let trackB = try #require((node.settings as? TimelineSettings)?.tracks[1])

        node.updateTrackName(id: trackB.id, name: "C")
        #expect(node.outputPorts().map(\.name) == ["A", "C"])
        #expect(node.outputPorts().first?.id == portA.id)
    }

    @Test("A track renamed to another track's name keeps its own, and both keep their ports")
    func timelineRenameRefusesANameInUse() throws
    {
        guard let context = makeContext() else { return }
        let node = TimelineNode(context: context)
        var settings = TimelineSettings(duration: 1, tracks: [])
        settings.addTrack()
        settings.addTrack()
        node.setSettings(settings)
        let trackTwo = try #require((node.settings as? TimelineSettings)?.tracks[1])
        let portIDs = node.outputPorts().map(\.id)

        node.updateTrackName(id: trackTwo.id, name: "Track 1")
        #expect((node.settings as? TimelineSettings)?.tracks.map(\.name) == ["Track 1", "Track 2"])
        #expect(node.outputPorts().map(\.id) == portIDs)

        node.updateTrackName(id: trackTwo.id, name: "Track 12")
        #expect((node.settings as? TimelineSettings)?.tracks.map(\.name) == ["Track 1", "Track 12"])
        #expect(node.outputPorts().map(\.name) == ["Track 1", "Track 12"])
        #expect(node.outputPorts().first?.id == portIDs.first)
    }

    @Test("Applying a timeline value keeps its keyframes as given, whatever the node's duration was")
    func timelineApplyKeepsTheGivenKeyframes() throws
    {
        guard let context = makeContext() else { return }
        let node = TimelineNode(context: context, settings: TimelineSettings(duration: 1, tracks: [TimelineTrack(name: "A", duration: 1)]))
        let settings = TimelineSettings(duration: 2, tracks: [TimelineTrack(name: "A", duration: 1)])

        node.setSettings(settings)
        #expect(node.settings?.isEqual(to: settings) == true)

        var lengthened = settings
        lengthened.setDuration(3)
        #expect(lengthened.tracks[0].keyframes.map(\.time) == settings.tracks[0].keyframes.map(\.time))
        var shortened = TimelineSettings(duration: 1, tracks: [TimelineTrack(name: "A", duration: 1)])
        shortened.setDuration(0.5)
        #expect(shortened.tracks[0].keyframes.last?.time == 0.5)
    }

    @Test("The strategy picker shows the node's strategy however it changed, and picks the old one again")
    func strategyPickerFollowsTheNode() async throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let node = SampleAndHoldNode(context: context, initialStrategy: PortType.Float.rawValue)
        graph.addNode(node)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        graph.undoManager = undoManager
        let model = node.strategySettingsModel

        // The model follows the node on a later turn of main.
        func runMainLoop() async throws { try await Task.sleep(for: .milliseconds(50)) }

        undoManager.beginUndoGrouping()
        node.setStrategy(PortType.String.rawValue)
        undoManager.endUndoGrouping()
        try await runMainLoop()
        #expect(model.strategy == PortType.String.rawValue)

        undoManager.beginUndoGrouping()
        node.setSettings(StrategyNodeSettings(strategy: PortType.Int.rawValue))
        undoManager.endUndoGrouping()
        try await runMainLoop()
        #expect(model.strategy == PortType.Int.rawValue)

        undoManager.beginUndoGrouping()
        model.strategy = PortType.Float.rawValue
        undoManager.endUndoGrouping()
        #expect(node.strategy == PortType.Float.rawValue)

        undoManager.undo()
        #expect(node.strategy == PortType.Int.rawValue)
        try await runMainLoop()
        #expect(model.strategy == PortType.Int.rawValue)
        #expect(node.strategy == PortType.Int.rawValue)

        // The model's update after a run of changes reads the node's strategy as it is then.
        undoManager.beginUndoGrouping()
        node.setSettings(StrategyNodeSettings(strategy: PortType.String.rawValue))
        node.setSettings(StrategyNodeSettings(strategy: PortType.Bool.rawValue))
        undoManager.endUndoGrouping()
        try await runMainLoop()
        #expect(node.strategy == PortType.Bool.rawValue)
        #expect(model.strategy == PortType.Bool.rawValue)

        // A change made off main reaches the model on main.
        undoManager.beginUndoGrouping()
        DispatchQueue.global().sync { node.setStrategy(PortType.Float.rawValue) }
        undoManager.endUndoGrouping()
        try await runMainLoop()
        #expect(model.strategy == PortType.Float.rawValue)
    }

    @Test("An open code editor takes a value applied under it, and an edit made in it still wins")
    func openCodeEditorFollowsAppliedSettings() async throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context, settings: JavaScriptSettings(scriptSource: """
        function main(value: Number): { doubled: Number }
        {
            return { doubled: value * 2 }
        }
        """))
        let editor = node.editorModel

        node.setSettings(JavaScriptSettings(scriptSource: """
        function main(value: Number): { tripled: Number }
        {
            return { tripled: value * 3 }
        }
        """, selectedTimeMode: .Idle))
        let applied = node.scriptSource
        #expect(applied != editor.content)

        // The editor takes the value on a later turn of main.
        try await Task.sleep(for: .milliseconds(50))
        #expect(editor.content == applied)
        #expect(editor.selectedTimeMode == .Idle)

        editor.flush()
        #expect(node.scriptSource == applied)
        #expect(node.selectedTimeMode == .Idle)

        editor.content = """
        function main(value: Number): { halved: Number }
        {
            return { halved: value / 2 }
        }
        """
        editor.flush()
        #expect(node.scriptSource != applied)
        #expect(node.findPort(named: "halved") != nil)
    }

    @Test("setSettings with another node's settings type changes nothing")
    func setSettingsIgnoresAnotherSettingsType() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let node = DistanceNode(context: context)
        graph.addNode(node)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        graph.undoManager = undoManager
        let settings = node.settings
        let portIDs = node.ports.map(\.id)

        undoManager.beginUndoGrouping()
        node.setSettings(KeyboardSettings(keyBindings: [nil]))
        node.setSettings(RoutingSettings(portType: .Int, routeCount: 3))
        undoManager.endUndoGrouping()

        #expect(settings.map { node.settings?.isEqual(to: $0) == true } == true)
        #expect(node.ports.map(\.id) == portIDs)
        #expect(undoManager.undoActionName != "Change Node Strategy")
    }

    @Test("A script that does not compile leaves the ports where they are")
    func uncompilableScriptKeepsThePorts() throws
    {
        guard let context = makeContext() else { return }
        let node = JavaScriptNode(context: context, settings: JavaScriptSettings(scriptSource: """
        function main(value: Number): { doubled: Number }
        {
            return { doubled: value * 2 }
        }
        """))
        let portIDs = node.ports.map(\.id)

        node.setSettings(JavaScriptSettings(scriptSource: """
        function main(value: Number  {
            return { doubled: value * 2 }
        }
        """))
        #expect(node.ports.map(\.id) == portIDs)
        #expect(Set(node.ports.map(\.id)).count == node.ports.count)
    }

    @Test("Applying another strategy in a graph records no step, and the replaced ports keep their connections")
    func strategyApplyInAGraphRecordsNoStep() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let source = SwitchNode(context: context, routeCount: 2, portType: .Virtual)
        let node = SwitchNode(context: context, routeCount: 2, portType: .Virtual)
        let log = LogNode(context: context)
        graph.addNode(source)
        graph.addNode(node)
        graph.addNode(log)
        let input = try #require(node.findPort(named: "input0", as: Fabric.Port.self))
        graph.connect(source.output, to: input)
        graph.connect(node.output, to: log.inputAny)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        graph.undoManager = undoManager

        undoManager.beginUndoGrouping()
        node.apply(RoutingSettings(portType: .Float, routeCount: 2))
        undoManager.endUndoGrouping()

        // An empty group still counts for canUndo; a registration names it.
        #expect(undoManager.undoActionName.isEmpty)
        #expect(node.output.portType == .Float)
        let replacedInput = try #require(node.findPort(named: "input0", as: Fabric.Port.self))
        #expect(replacedInput.id == input.id)
        #expect(replacedInput.portType == .Float)
        #expect(replacedInput.connections.count == 1)
        #expect(node.output.connections.count == 1)
        #expect(graph.connections.count == 2)
    }

    @Test("A HID node with its device absent gives back the value committed, and committing it again leaves the ports")
    func hidCommitWithDeviceAbsentIsIdempotent() throws
    {
        guard let context = makeContext() else { return }
        let element = HIDElementInfo(id: "axis-x", cookie: 1, usagePage: 1, usage: 0x30,
                                     displayName: "X", min: 0, max: 255, isRelative: false)
        let settings = HIDSettings(selectedDeviceID: "absent", deviceElements: [element])
        let node = HIDNode(context: context)

        node.setSettings(settings)
        #expect(node.settings?.isEqual(to: settings) == true)
        let portIDs = node.ports.map(\.id)

        node.setSettings(settings)
        node.apply(settings)
        #expect(node.ports.map(\.id) == portIDs)
        #expect(node.settings?.isEqual(to: settings) == true)
    }

    @Test("A timeline given no tracks keeps one, with its port")
    func timelineGivenNoTracksKeepsOne() throws
    {
        guard let context = makeContext() else { return }
        let node = TimelineNode(context: context, settings: TimelineSettings(duration: 1, tracks: [TimelineTrack(name: "A", duration: 1),
                                                                                                    TimelineTrack(name: "B", duration: 1)]))

        node.setSettings(TimelineSettings(duration: 1, tracks: []))
        let tracks = try #require((node.settings as? TimelineSettings)?.tracks)
        #expect(tracks.count == 1)
        #expect(node.outputPorts().map(\.name) == tracks.map(\.name))
    }

    @Test("A timeline given two tracks of one name renames the later one, so each has a port")
    func timelineGivenDuplicateTrackNamesRenamesTheLater() throws
    {
        guard let context = makeContext() else { return }
        let node = TimelineNode(context: context, settings: TimelineSettings(duration: 1, tracks: [TimelineTrack(name: "A", duration: 1),
                                                                                                    TimelineTrack(name: "A", duration: 1),
                                                                                                    TimelineTrack(name: "Track 4", duration: 1)]))
        let tracks = try #require((node.settings as? TimelineSettings)?.tracks)
        #expect(tracks.map(\.name) == ["A", "Track 5", "Track 4"])
        #expect(node.outputPorts().map(\.name) == tracks.map(\.name))
    }

    @Test("Saving a Live Image node writes the shader on disk and leaves the node holding it")
    func liveImageSaveCapturesTheShaderOnDisk() throws
    {
        guard let context = makeContext() else { return }
        let node = LiveImageNode(context: context)
        let held = try #require((node.settings as? LiveImageSettings)?.shaderSource)

        // The workspace is private to the node; it is found by the node's id.
        let nodeWorkspace = URL(filePath: "/tmp/fabric-live-shaders", directoryHint: .isDirectory)
            .appending(path: "unsaved-document")
            .appending(path: node.id.uuidString, directoryHint: .isDirectory)
        let instance = try #require(try FileManager.default.contentsOfDirectory(at: nodeWorkspace, includingPropertiesForKeys: nil).first)
        let shaderFile = instance.appending(path: "Shaders.metal")
        let edited = held + "\n// Edited in another editor.\n"
        try edited.write(to: shaderFile, atomically: false, encoding: .utf8)

        // Settings give the source the node holds until a save captures the file.
        #expect((node.settings as? LiveImageSettings)?.shaderSource == held)

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(node)) as? [String: Any]
        #expect(json?["shaderSource"] as? String == edited)
        #expect((node.settings as? LiveImageSettings)?.shaderSource == edited)
    }

    @Test("Applying a Live Image node's own settings leaves the shader file, the ports and the status as they are")
    func liveImageApplyingItsOwnSettingsIsNoChange() throws
    {
        guard let context = makeContext() else { return }
        let node = LiveImageNode(context: context)
        let settings = try #require(node.settings)

        let nodeWorkspace = URL(filePath: "/tmp/fabric-live-shaders", directoryHint: .isDirectory)
            .appending(path: "unsaved-document")
            .appending(path: node.id.uuidString, directoryHint: .isDirectory)
        let instance = try #require(try FileManager.default.contentsOfDirectory(at: nodeWorkspace, includingPropertiesForKeys: nil).first)
        let shaderFile = instance.appending(path: "Shaders.metal")
        let modified = try shaderFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let portIDs = node.ports.map(\.id)
        let statuses = node.deriveStatuses()

        node.apply(settings)
        var refreshed = shaderFile
        refreshed.removeAllCachedResourceValues()
        #expect(try refreshed.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        #expect(node.ports.map(\.id) == portIDs)
        #expect(node.deriveStatuses() == statuses)
    }

    // MARK: - Saving

    @Test("Undoing a strategy change puts back the strategy, and keeps a route count changed after it")
    func strategyUndoPutsBackTheStrategy() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let node = SwitchNode(context: context, routeCount: 2, portType: .Float)
        graph.addNode(node)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        graph.undoManager = undoManager

        // The undo step covers the strategy; a route count changed in the same value stays.
        undoManager.beginUndoGrouping()
        node.setSettings(RoutingSettings(portType: .Int, routeCount: 5))
        undoManager.endUndoGrouping()
        #expect(node.settings?.isEqual(to: RoutingSettings(portType: .Int, routeCount: 5)) == true)
        #expect(undoManager.undoActionName == "Change Node Strategy")

        undoManager.undo()
        #expect(node.settings?.isEqual(to: RoutingSettings(portType: .Float, routeCount: 5)) == true)

        undoManager.redo()
        #expect(node.settings?.isEqual(to: RoutingSettings(portType: .Int, routeCount: 5)) == true)

        // A type picked, then a route count changed, which records no step.
        let picked = SwitchNode(context: context, routeCount: 2, portType: .Float)
        graph.withoutUndoRegistration { graph.addNode(picked) }
        undoManager.beginUndoGrouping()
        picked.setPortType(.Int)
        undoManager.endUndoGrouping()
        picked.setRouteCount(4)
        let portIDs = Set(picked.ports.map(\.id))
        #expect(picked.ports.count > SwitchNode(context: context, routeCount: 2, portType: .Float).ports.count)

        undoManager.undo()
        #expect(picked.settings?.isEqual(to: RoutingSettings(portType: .Float, routeCount: 4)) == true)
        #expect(Set(picked.ports.map(\.id)) == portIDs)
    }

    @Test("A game controller that is unplugged keeps its saved port set through apply")
    func unpluggedGameControllerKeepsItsSavedPorts() throws
    {
        guard let context = makeContext() else { return }
        let descriptors = [DeviceOutputPortDescriptor(name: "Button A", isButton: true),
                           DeviceOutputPortDescriptor(name: "Left Thumbstick X", isButton: false)]
        let settings = GameControllerSettings(selectedControllerID: "not-plugged-in", portDescriptors: descriptors)
        let node = GameControllerNode(context: context, settings: settings)
        #expect(node.outputPorts().map(\.name) == descriptors.map(\.name))

        node.apply(GameControllerSettings(selectedControllerID: "not-plugged-in", portDescriptors: descriptors))
        #expect(node.outputPorts().map(\.name) == descriptors.map(\.name))
        #expect(node.settings?.isEqual(to: settings) == true)

        // Selecting another unplugged controller with the same ports keeps them.
        let portIDs = node.outputPorts().map(\.id)
        let other = GameControllerSettings(selectedControllerID: "also-not-plugged-in", portDescriptors: descriptors)
        node.apply(other)
        #expect(node.outputPorts().map(\.id) == portIDs)
        #expect(node.settings?.isEqual(to: other) == true)
    }

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
