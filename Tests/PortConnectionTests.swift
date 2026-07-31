import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

@Suite("Port Connection")
struct PortConnectionTests {

    private func makeContext() -> Context? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
    }

    @Test("Connecting an already-connected pair does not clear the inlet value")
    func duplicateConnectIsNoOp() throws {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let source = NumberBinaryOperator(context: context)
        let sink = NumberBinaryOperator(context: context)
        graph.addNode(source)
        graph.addNode(sink)

        source.outputNumber.connect(to: sink.inputNumber1)
        sink.inputNumber1.value = 72

        // Duplicate connect from the outlet side, as the decode connection
        // restore does for the outlet-keyed map entry. The source outlet has
        // no value yet, so a disconnect/reconnect would leave the inlet nil.
        source.outputNumber.connect(to: sink.inputNumber1)
        #expect(sink.inputNumber1.value == 72)
        #expect(source.outputNumber.connections.count == 1)
        #expect(sink.inputNumber1.connections.count == 1)

        // ...and from the inlet side, for the inlet-keyed map entry.
        sink.inputNumber1.connect(to: source.outputNumber)
        #expect(sink.inputNumber1.value == 72)
        #expect(source.outputNumber.connections.count == 1)
        #expect(sink.inputNumber1.connections.count == 1)
    }

    @Test("Decoded ParameterPort value survives connection restore")
    func decodedParameterValueSurvivesConnectionRestore() throws {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let source = NumberBinaryOperator(context: context)
        let sink = NumberBinaryOperator(context: context)
        graph.addNode(source)
        graph.addNode(sink)

        source.outputNumber.connect(to: sink.inputNumber1)
        sink.inputNumber1.value = 72

        let data = try JSONEncoder().encode(graph)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(Graph.self, from: data)

        let decodedSink = try #require(
            decoded.nodes.first { $0.id == sink.id } as? NumberBinaryOperator
        )
        #expect(decodedSink.inputNumber1.value == 72)
        #expect(decodedSink.inputNumber1.connections.count == 1)

        let decodedSource = try #require(
            decoded.nodes.first { $0.id == source.id } as? NumberBinaryOperator
        )
        #expect(decodedSource.outputNumber.connections.count == 1)
        #expect(decodedSource.outputNumber.connectedInlets == [decodedSink.inputNumber1])
        #expect(decodedSink.inputNumber1.connectedOutlets == [decodedSource.outputNumber])

        decodedSource.outputNumber.send(144)
        #expect(decodedSink.inputNumber1.value == 144)
    }

    @Test("Graph encoding records required plugins and qualified node IDs")
    func graphEncodingRecordsRequiredPluginsAndQualifiedNodeIDs() throws {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        graph.addNode(PerspectiveCameraNode(context: context))

        let data = try JSONEncoder().encode(graph)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let requiredPlugins = try #require(object?["requiredPlugins"] as? [[String: Any]])
        let nodeMap = try #require(object?["nodeMap"] as? [[String: Any]])

        #expect(requiredPlugins.contains { $0["id"] as? String == PluginLoader.coreNodesPluginID })
        #expect(nodeMap.first?["type"] as? String == "\(PluginLoader.coreNodesPluginID)/PerspectiveCameraNode")
    }

    @Test("Legacy unqualified node IDs decode as core plugin nodes")
    func legacyUnqualifiedNodeIDsDecodeAsCorePluginNodes() throws {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        graph.addNode(PerspectiveCameraNode(context: context))

        let encodedData = try JSONEncoder().encode(graph)
        var object = try #require(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        var nodeMap = try #require(object["nodeMap"] as? [[String: Any]])
        nodeMap[0]["type"] = "PerspectiveCameraNode"
        object["nodeMap"] = nodeMap
        object.removeValue(forKey: "requiredPlugins")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decodedGraph = try decoder.decode(Graph.self, from: legacyData)

        #expect(decodedGraph.nodes.first is PerspectiveCameraNode)
    }

    @Test("Generic array virtual type compatibility is array scoped")
    func genericArrayVirtualTypeCompatibilityIsArrayScoped() {
        let genericArray = PortType.Array(portType: .Virtual)

        #expect(genericArray.canConnect(to: .Array(portType: .Float)))
        #expect(genericArray.canConnect(to: .Array(portType: .String)))
        #expect(genericArray.canConnect(to: genericArray))

        #expect(!genericArray.canConnect(to: .Float))
        #expect(!genericArray.canConnect(to: .String))
        #expect(!genericArray.canConnect(to: .Virtual))
    }

    @Test("Generic array virtual inlets reject scalar outlets")
    func genericArrayVirtualInletsRejectScalarOutlets() {
        let arrayInlet = PortType.Array(portType: .Virtual).makeFreshPort(name: "Array", kind: .Inlet)
        let scalarOutlet = PortType.Float.makeFreshPort(name: "Float", kind: .Outlet)
        let virtualOutlet = PortType.Virtual.makeFreshPort(name: "Value", kind: .Outlet)
        let concreteArrayOutlet = PortType.Array(portType: .Float).makeFreshPort(name: "Array", kind: .Outlet)

        #expect(!arrayInlet.canConnect(to: scalarOutlet))
        #expect(!arrayInlet.canConnect(to: virtualOutlet))
        #expect(arrayInlet.canConnect(to: concreteArrayOutlet))
    }

    @Test("Pure virtual inlets remain universal")
    func pureVirtualInletsRemainUniversal() {
        let virtualInlet = PortType.Virtual.makeFreshPort(name: "Value", kind: .Inlet)
        let concreteArrayOutlet = PortType.Array(portType: .Float).makeFreshPort(name: "Array", kind: .Outlet)
        let genericArrayOutlet = PortType.Array(portType: .Virtual).makeFreshPort(name: "Array", kind: .Outlet)

        #expect(virtualInlet.canConnect(to: concreteArrayOutlet))
        #expect(virtualInlet.canConnect(to: genericArrayOutlet))
    }

    @Test("Pure virtual outlets connect to typed inlets from either compatibility direction")
    func pureVirtualOutletsRemainUniversal() {
        let virtualOutlet = PortType.Virtual.makeFreshPort(name: "Value", kind: .Outlet)
        let stringInlet = PortType.String.makeFreshPort(name: "String", kind: .Inlet)

        #expect(virtualOutlet.canConnect(to: stringInlet))
        #expect(stringInlet.canConnect(to: virtualOutlet))
    }

    /// Every port type the canvas can present, including the two virtual types
    /// and a representative concrete and generic array.
    private static let allConnectablePortTypes: [PortType] = [
        .Virtual, .NumericVirtual,
        .Bool, .Int, .Float, .String,
        .Vector2, .Vector3, .Vector4, .Color, .Quaternion, .Transform,
        .Geometry, .Material, .Image,
        .Array(portType: .Virtual), .Array(portType: .Float),
    ]

    @Test("Compatibility is direction independent for every port type pair")
    func compatibilityIsDirectionIndependent() {
        // The canvas asks compatibility as targetPort.canConnect(to: draggedPort),
        // so whichever end the user drags from decides which type is the receiver.
        // Any asymmetry here makes a wire connect one way and silently fail the other.
        for outlet in Self.allConnectablePortTypes {
            for inlet in Self.allConnectablePortTypes {
                #expect(outlet.canConnect(to: inlet) == inlet.canConnect(to: outlet),
                        "\(outlet.rawValue) -> \(inlet.rawValue) disagrees with the reverse direction")
            }
        }
    }

    @Test("Every scalar type connects to a virtual port from either drag direction")
    func scalarTypesConnectToVirtualFromEitherDragDirection() {
        // Regression: the .Bool/.Int/.Float/.String and .Color/.Vector4 cases used
        // to omit .Virtual from their accepted set, so a virtual outlet could not
        // be dragged into a typed inlet even though the reverse drag worked.
        for portType in [PortType.Bool, .Int, .Float, .String, .Vector4, .Color] {
            let typedInlet = portType.makeFreshPort(name: "Typed", kind: .Inlet)
            let typedOutlet = portType.makeFreshPort(name: "Typed", kind: .Outlet)
            let virtualInlet = PortType.Virtual.makeFreshPort(name: "Value", kind: .Inlet)
            let virtualOutlet = PortType.Virtual.makeFreshPort(name: "Value", kind: .Outlet)

            #expect(typedInlet.canConnect(to: virtualOutlet),
                    "dragging a virtual outlet onto a \(portType.rawValue) inlet must be allowed")
            #expect(virtualOutlet.canConnect(to: typedInlet),
                    "dragging a \(portType.rawValue) inlet onto a virtual outlet must be allowed")
            #expect(virtualInlet.canConnect(to: typedOutlet),
                    "dragging a \(portType.rawValue) outlet onto a virtual inlet must be allowed")
            #expect(typedOutlet.canConnect(to: virtualInlet),
                    "dragging a virtual inlet onto a \(portType.rawValue) outlet must be allowed")
        }
    }

    @Test("A typed Switch wires up everywhere its virtual form does")
    func typedSwitchConnectsWhereVirtualSwitchDoes() throws {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let virtualSwitch = SwitchNode(context: context, routeCount: 2, portType: .Virtual)
        let floatSwitch = SwitchNode(context: context, routeCount: 2, portType: .Float)
        let log = LogNode(context: context)
        let number = NumberBinaryOperator(context: context)
        graph.addNode(virtualSwitch)
        graph.addNode(floatSwitch)
        graph.addNode(log)
        graph.addNode(number)

        let floatInput = try #require(floatSwitch.findPort(named: "input0", as: Port.self))

        // Switch output into the virtual Log inlet, dragged from either end.
        #expect(log.inputAny.canConnect(to: floatSwitch.output))
        #expect(floatSwitch.output.canConnect(to: log.inputAny))

        // Switch output into a typed number inlet, and a number outlet back into
        // the typed Switch input.
        #expect(number.inputNumber1.canConnect(to: floatSwitch.output))
        #expect(floatInput.canConnect(to: number.outputNumber))

        // A virtual outlet into the typed Switch input — the case the canvas
        // refused while the reverse drag succeeded.
        #expect(floatInput.canConnect(to: virtualSwitch.output))
        #expect(virtualSwitch.output.canConnect(to: floatInput))

        floatSwitch.output.connect(to: log.inputAny)
        number.outputNumber.connect(to: floatInput)

        #expect(floatSwitch.output.connections.count == 1)
        #expect(log.inputAny.connections.count == 1)
        #expect(number.outputNumber.connections.count == 1)
        #expect(floatInput.connections.count == 1)
    }

    @Test("Switching a Switch from virtual to typed keeps its wires")
    func switchTypeChangeKeepsWires() throws {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let source = SwitchNode(context: context, routeCount: 2, portType: .Virtual)
        let sink = SwitchNode(context: context, routeCount: 2, portType: .Virtual)
        let log = LogNode(context: context)
        graph.addNode(source)
        graph.addNode(sink)
        graph.addNode(log)

        let inputBefore = try #require(sink.findPort(named: "input0", as: Port.self))
        source.output.connect(to: inputBefore)
        sink.output.connect(to: log.inputAny)

        sink.setPortType(.Float)

        // Ports are replaced in place on a type change; the surviving wires are
        // re-attached only for pairs canConnect still accepts.
        let inputAfter = try #require(sink.findPort(named: "input0", as: Port.self))
        let outputAfter = try #require(sink.findPort(named: "output", as: Port.self))

        #expect(inputAfter.connections.count == 1)
        #expect(outputAfter.connections.count == 1)
        #expect(source.output.connections.count == 1)
        #expect(log.inputAny.connections.count == 1)
    }

    @Test("Retired dynamic ports cannot reconnect from stale view references")
    func retiredDynamicPortsCannotReconnect() throws {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let arrayValue = ArrayIndexValueNode(context: context, portType: .String)
        let stringSink = PassThroughNode<String>(context: context)
        graph.addNode(arrayValue)
        graph.addNode(stringSink)

        let retiredOutput = try #require(
            arrayValue.findPort(named: "outputPort", as: NodePort<String>.self)
        )

        arrayValue.rebuildPorts(forStrategy: PortType.Float.rawValue)

        #expect(retiredOutput.node == nil)
        retiredOutput.connect(to: stringSink.input)
        #expect(retiredOutput.connections.isEmpty)
        #expect(stringSink.input.connections.isEmpty)
    }

    @Test("String array value output connects to 3D Text Geometry")
    func stringArrayValueConnectsToExtrudedTextGeometry() throws {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let arrayValue = ArrayIndexValueNode(context: context, portType: .String)
        let textGeometry = ExtrudedTextGeometryNode(context: context)
        graph.addNode(arrayValue)
        graph.addNode(textGeometry)

        let stringOutput = try #require(
            arrayValue.findPort(named: "outputPort", as: NodePort<String>.self)
        )

        #expect(stringOutput.canConnect(to: textGeometry.inputText))
        #expect(textGeometry.inputText.canConnect(to: stringOutput))

        stringOutput.connect(to: textGeometry.inputText)

        #expect(stringOutput.connectedPorts == [textGeometry.inputText])
        #expect(textGeometry.inputText.connectedPorts == [stringOutput])
    }

    @Test("Virtual strategy array nodes expose generic array ports")
    func virtualStrategyArrayNodesExposeGenericArrayPorts() throws {
        guard let context = makeContext() else { return }

        let arrayCount = ArrayCountNode(context: context, portType: .Virtual)
        let countInput: Fabric.Port = arrayCount.port(named: "inputPort")
        #expect(countInput.portType == .Array(portType: .Virtual))

        let firstValue = ArrayFirstValueNode(context: context, portType: .Virtual)
        let firstInput: Fabric.Port = firstValue.port(named: "inputPort")
        let firstOutput: Fabric.Port = firstValue.port(named: "outputPort")
        #expect(firstInput.portType == .Array(portType: .Virtual))
        #expect(firstOutput.portType == .Virtual)

        let queue = ArrayQueueNode(context: context, portType: .Virtual)
        let queueInput: Fabric.Port = queue.port(named: "inputPort")
        let queueOutput: Fabric.Port = queue.port(named: "outputPort")
        #expect(queueInput.portType == .Virtual)
        #expect(queueOutput.portType == .Array(portType: .Virtual))
    }
}
