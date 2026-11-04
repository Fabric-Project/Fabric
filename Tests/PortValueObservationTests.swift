import Testing
import Foundation
import Metal
import Satin
@testable import Fabric

@Suite("Port value observation", .serialized)
struct PortValueObservationTests
{
    private func context() throws -> Context
    {
        Context(device: try #require(MTLCreateSystemDefaultDevice()), sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    @Test("Observers hear every change on the sending thread until removed")
    func observersHearChanges()
    {
        let port = NodePort<Float>(name: "Value", kind: .Inlet)
        var heard = 0
        let observation = port.addValueObserver { heard += 1 }

        port.send(1)
        port.send(1)
        port.send(2)
        #expect(heard == 2)

        port.removeValueObserver(observation)
        port.send(3)
        #expect(heard == 2)
    }

    @Test("A control follows its port with one main hop for a burst of sends")
    func controlFollowsPort() async throws
    {
        let node = NumberBinaryOperator(context: try context())
        let graph = Graph(context: node.context)
        graph.addNode(node)
        let parameter = try #require(node.inputNumber1.parameter as? FloatParameter)
        let model = await MainActor.run {
            ParameterObservableModel(control: ControlValue(parameter: parameter, port: node.inputNumber1),
                                     publisher: parameter.valuePublisher)
        }

        await Task.detached {
            for value in 1...100 { node.inputNumber1.send(Float(value)) }
        }.value
        var value = await MainActor.run { model.uiValue }
        for _ in 0..<100 where value != 100
        {
            try await Task.sleep(for: .milliseconds(10))
            value = await MainActor.run { model.uiValue }
        }
        #expect(value == 100)

        await MainActor.run { model.uiValue = 7 }
        #expect(node.inputNumber1.value == 7)
        withExtendedLifetime(graph) { }
    }
}
