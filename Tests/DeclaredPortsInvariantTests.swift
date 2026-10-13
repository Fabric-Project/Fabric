import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// A node's port set and order are a function of its declarations and its
/// settings value: equal settings give equal ports, in equal order, under equal
/// ids for surviving keys, however the node got there.
@Suite("Declared Ports Invariant")
@MainActor
struct DeclaredPortsInvariantTests
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

    /// A seeded generator, so a failing sequence can be run again.
    private struct SplitMix64: RandomNumberGenerator
    {
        var state: UInt64

        mutating func next() -> UInt64
        {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    private func keys(of node: Node) -> [String]
    {
        node.ports.compactMap { node.registryKey(of: $0) }
    }

    private func shape(of node: Node) -> [String]
    {
        node.ports.map { "\(node.registryKey(of: $0) ?? "?"):\($0.portType.rawValue):\($0.kind)" }
    }

    private func ids(of node: Node) -> [String: UUID]
    {
        Dictionary(node.ports.compactMap { port in node.registryKey(of: port).map { ($0, port.id) } },
                   uniquingKeysWith: { first, _ in first })
    }

    /// A node of `node`'s type made straight from `settings`, as a document
    /// holding them and no port state opens.
    private func freshNode(like node: Node, settings: any NodeSettings, context: Context) throws -> Node
    {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(node)) as? [String: Any])
        let settingsJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(AnySettings(settings))) as? [String: Any])
        json.merge(settingsJSON) { _, new in new }
        json["ports"] = []
        json["id"] = UUID().uuidString

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        return try decoder.decode(type(of: node), from: JSONSerialization.data(withJSONObject: json))
    }

    private struct AnySettings: Encodable
    {
        let settings: any NodeSettings
        init(_ settings: any NodeSettings) { self.settings = settings }
        func encode(to encoder: Encoder) throws { try settings.encode(to: encoder) }
    }

    // MARK: - Settings values

    private func spread<T>(_ values: [T], count: Int) -> [T]
    {
        guard values.count > count, count > 1 else { return values }
        return (0..<count).map { values[$0 * (values.count - 1) / (count - 1)] }
    }

    private func keyBinding(_ characters: String) throws -> KeyBinding
    {
        let json = #"{"characters":"\#(characters)","keyDescription":"\#(characters)","modifiersDescription":""}"#
        return try JSONDecoder().decode(KeyBinding.self, from: Data(json.utf8))
    }

    private func hidElement(_ id: String, name: String, button: Bool) -> HIDElementInfo
    {
        HIDElementInfo(id: id, cookie: id.hashValue, usagePage: button ? 9 : 1, usage: 48, displayName: name,
                       min: 0, max: button ? 1 : 255, isRelative: false)
    }

    /// A few distinct values of `node`'s settings, its own first.
    private func settingsValues(for node: Node) throws -> [any NodeSettings]
    {
        guard let current = node.settings else { return [] }
        var values: [any NodeSettings] = [current]

        switch current
        {
        case let routing as RoutingSettings:
            for strategy in spread(type(of: node as! StrategyNode).strategies, count: 3)
            {
                for routeCount in [2, 4]
                {
                    values.append(RoutingSettings(strategy: strategy, routeCount: routeCount))
                }
            }
            _ = routing
        case var strategy as any StrategySettings:
            for option in spread(type(of: node as! StrategyNode).strategies, count: 4)
            {
                strategy.strategy = option
                values.append(strategy)
            }
        case is MathExpressionSettings:
            values += ["x + y", "x", "in a: vec3; out o = a * x", "y * k", "x + y + 1"].map(MathExpressionSettings.init(stringExpression:))
        case is ParametricExpressionSettings:
            values += [
                ParametricExpressionSettings(expressionX: "u * a", expressionY: "v + b", expressionZ: "0"),
                ParametricExpressionSettings(expressionX: "u", expressionY: "v * c", expressionZ: "a"),
            ]
        case is FormatStringSettings:
            values += ["{a} and {b:d}", "{b:f}", "{c:b} then {a}", "none"].map(FormatStringSettings.init(formatString:))
        case let script as JavaScriptSettings:
            values += [
                "function main(b: Number, c: Bool): { sum: Number } {\n  return { sum: b }\n}",
                "function main(a: Number, b: String): { sum: Number, label: String } {\n  return { sum: a, label: b }\n}",
            ].map { JavaScriptSettings(scriptSource: $0, selectedTimeMode: script.selectedTimeMode) }
        case let shader as LiveImageSettings:
            let withGain = shader.shaderSource.replacing("float amount; // slider, 0.0, 1.0, 1.0, Amount",
                                                         with: "float gain; // slider, 0.0, 1.0, 0.5, Gain\n    float amount; // slider, 0.0, 1.0, 1.0, Amount")
            values.append(LiveImageSettings(shaderSource: withGain))
        case let timeline as TimelineSettings:
            let a = TimelineTrack(name: "A", duration: timeline.duration)
            let b = TimelineTrack(name: "B", duration: timeline.duration)
            let c = TimelineTrack(name: "C", duration: timeline.duration)
            values += [[a, b], [b], [c, a, b], [b, a]].map { TimelineSettings(duration: timeline.duration, tracks: $0) }
        case is KeyboardSettings:
            values += try [["a", "b"], ["b"], ["c", "a"]].map { try KeyboardSettings(keyBindings: $0.map(keyBinding)) }
        case is GameControllerSettings:
            values += [
                [DeviceOutputPortDescriptor(name: "X", isButton: false), DeviceOutputPortDescriptor(name: "A", isButton: true)],
                [DeviceOutputPortDescriptor(name: "A", isButton: true)],
                [DeviceOutputPortDescriptor(name: "A", isButton: false), DeviceOutputPortDescriptor(name: "B", isButton: true)],
            ].map { GameControllerSettings(selectedControllerID: nil, portDescriptors: $0) }
        case is HIDSettings:
            values += [
                [hidElement("1", name: "Trigger", button: true), hidElement("2", name: "Stick", button: false)],
                [hidElement("2", name: "Stick", button: false)],
                [hidElement("3", name: "Wheel", button: false), hidElement("1", name: "Trigger", button: true)],
            ].map { HIDSettings(selectedDeviceID: nil, deviceElements: $0) }
        case is MIDIInputSettings:
            let gate = DetectedMIDIInput(type: .noteGate, channel: 0, number: 60)
            let velocity = DetectedMIDIInput(type: .noteVelocity, channel: 0, number: 60)
            let other = DetectedMIDIInput(type: .noteGate, channel: 1, number: 62)
            values += [[gate, velocity], [velocity], [other, gate]].map { MIDIInputSettings(selectedInputID: nil, configuredInputs: $0) }
        case let osc as OSCReceiveSettings:
            values += [
                [OSCAddressBinding(address: "/a", dataType: .float), OSCAddressBinding(address: "/b", dataType: .bool)],
                [OSCAddressBinding(address: "/b", dataType: .int)],
                [OSCAddressBinding(address: "/c", dataType: .string), OSCAddressBinding(address: "/a", dataType: .float)],
            ].map { OSCReceiveSettings(listenPort: osc.listenPort, addressBindings: $0) }
        case let deferred as DeferredSubgraphSettings:
            values.append(DeferredSubgraphSettings(deferredMRTEnabled: !deferred.deferredMRTEnabled))
        default:
            break
        }

        return values
    }

    // MARK: - Every node

    @Test("Every core node with settings stands in declared order, with surviving keys' ids, through edits, undo and redo")
    func everyNodeFollowsItsDeclarations() throws
    {
        guard let context = makeContext() else { return }
        var failures: [String] = []
        var withoutVariation: [String] = []
        var checked = 0

        for wrapper in try NodeRegistry.shared.availableNodes
        {
            guard let node = try? wrapper.initializeNode(context: context), node.settings != nil else { continue }
            let name = wrapper.nodeClass.name
            let values = try settingsValues(for: node)
            if values.count < 2 { withoutVariation.append(name) }

            let graph = Graph(context: context)
            let undoManager = UndoManager()
            undoManager.groupsByEvent = false
            graph.undoManager = undoManager
            undoManager.beginUndoGrouping()
            graph.addNode(node)
            undoManager.endUndoGrouping()

            var generator = SplitMix64(state: UInt64(checked) &+ 7)
            // The edits this sequence can undo and redo; the add is not one.
            var undoable = 0
            var redoable = 0
            for step in 1...12
            {
                let before = ids(of: node)
                let choice = Int(generator.next() % 4)
                let action: String
                if choice == 0, undoable > 0
                {
                    graph.undo()
                    undoable -= 1
                    redoable += 1
                    action = "undo"
                }
                else if choice == 1, redoable > 0
                {
                    graph.redo()
                    redoable -= 1
                    undoable += 1
                    action = "redo"
                }
                else
                {
                    let value = values[Int(generator.next() % UInt64(values.count))]
                    let records = node.settings.map { !$0.isEqual(to: value) } ?? false
                    undoManager.beginUndoGrouping()
                    graph.setSettings(value, on: node)
                    undoManager.endUndoGrouping()
                    if records
                    {
                        undoable += 1
                        redoable = 0
                    }
                    action = "set"
                }

                guard let current = node.settings else { continue }
                let fresh = try freshNode(like: node, settings: current, context: context)
                if shape(of: node) != shape(of: fresh)
                {
                    failures.append("\(name) after step \(step) (\(action)): \(shape(of: node)) but fresh \(shape(of: fresh))")
                    break
                }

                let after = ids(of: node)
                let changed = after.filter { key, id in before[key].map { $0 != id } ?? false }
                if !changed.isEmpty
                {
                    failures.append("\(name) after step \(step) (\(action)): \(changed.keys.sorted()) changed id")
                    break
                }
            }
            checked += 1
        }

        #expect(checked > 50)
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        // Their settings have nothing that shapes ports, so one value checks them.
        #expect(Set(withoutVariation).isSubset(of: ["Local LLM Node", "Local VLM Node"]), "\(withoutVariation)")
    }

    // MARK: - Cases named

    @Test("Math Expression: x + y, then x, then undo stands y before result, under its own id")
    func mathExpressionUndoKeepsDeclaredOrder() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        graph.undoManager = undoManager
        let node = MathExpressionNode(context: context, settings: MathExpressionSettings(stringExpression: "x + y"))
        undoManager.beginUndoGrouping()
        graph.addNode(node)
        undoManager.endUndoGrouping()
        let original = ids(of: node)
        let declared = keys(of: node)

        undoManager.beginUndoGrouping()
        graph.setSettings(MathExpressionSettings(stringExpression: "x"), on: node)
        undoManager.endUndoGrouping()
        #expect(!keys(of: node).contains("y"))

        graph.undo()
        #expect(keys(of: node) == declared)
        #expect(keys(of: node) == keys(of: MathExpressionNode(context: context, settings: MathExpressionSettings(stringExpression: "x + y"))))
        #expect(ids(of: node) == original)

        graph.redo()
        #expect(keys(of: node) == keys(of: MathExpressionNode(context: context, settings: MathExpressionSettings(stringExpression: "x"))))
    }

    @Test("A document saved with its dynamic ports out of declared order opens in declared order, every wire kept")
    func driftedDocumentOpensInDeclaredOrder() throws
    {
        guard let context = makeContext() else { return }
        let graph = Graph(context: context)
        let switchNode = SwitchNode(context: context, routeCount: 3, portType: .Float)
        let upstream = NumberBinaryOperator(context: context)
        let downstream = NumberBinaryOperator(context: context)
        graph.addNode(switchNode)
        graph.addNode(upstream)
        graph.addNode(downstream)
        for key in ["input0", "input1", "input2"]
        {
            graph.connect(upstream.outputNumber, to: try #require(switchNode.findPort(named: key) as Fabric.Port?))
        }
        graph.connect(switchNode.output, to: downstream.inputNumber1)
        let declared = keys(of: switchNode)
        let wires = Set(graph.connections.map { "\($0.outletPortID)>\($0.inletPortID)" })

        // The order an older build left behind: the output first, the routes
        // in the order they were last retyped.
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(graph)) as? [String: Any])
        var nodeMap = try #require(json["nodeMap"] as? [[String: Any]])
        let index = try #require(nodeMap.firstIndex { ($0["value"] as? [String: Any])?["id"] as? String == switchNode.id.uuidString })
        var nodeJSON = try #require(nodeMap[index]["value"] as? [String: Any])
        var ports = try #require(nodeJSON["ports"] as? [[String: Any]])
        let drift = ["output", "input2", "inputIndex", "input0", "input1"]
        ports.sort { lhs, rhs in
            (drift.firstIndex(of: lhs["name"] as? String ?? "") ?? 0) < (drift.firstIndex(of: rhs["name"] as? String ?? "") ?? 0)
        }
        #expect(ports.compactMap { $0["name"] as? String } == drift)
        nodeJSON["ports"] = ports
        nodeMap[index]["value"] = nodeJSON
        json["nodeMap"] = nodeMap

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(Graph.self, from: JSONSerialization.data(withJSONObject: json))
        let decodedSwitch = try #require(decoded.node(forID: switchNode.id))

        #expect(keys(of: decodedSwitch) == declared)
        #expect(Set(decoded.connections.map { "\($0.outletPortID)>\($0.inletPortID)" }) == wires)
        #expect(decoded.connections.allSatisfy { $0.inletPort != nil && $0.outletPort != nil })
    }
}
