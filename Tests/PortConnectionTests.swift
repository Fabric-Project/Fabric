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
