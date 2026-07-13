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
}
