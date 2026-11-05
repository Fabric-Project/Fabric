import Testing
import Foundation
import Metal
import Satin
@testable import Fabric

/// A node learns of a change to its inputs from its ports' values alone; it
/// observes no parameter.
@Suite("Node parameter observation", .serialized)
struct NodeParameterObservationTests {
    private func context() throws -> Context {
        Context(device: try #require(MTLCreateSystemDefaultDevice()), sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    @Test("A port edit invalidates its node and reaches the parameter")
    func portEditInvalidates() throws {
        let node = NumberBinaryOperator(context: try context())
        let parameter = try #require(node.inputNumber1.parameter as? FloatParameter)
        node.markClean()
        node.inputNumber1.value = 3
        #expect(parameter.value == 3)
        #expect(node.inputNumber1.valueDidChange)
        #expect(node.isDirty)

        node.markClean()
        node.inputNumber1.send(3, force: true)
        #expect(node.isDirty)
        #expect(node.inputNumber1.valueDidChange)
    }

    @Test("A parameter edit neither reaches the port nor invalidates the node")
    func parameterEditIsInert() throws {
        let node = NumberBinaryOperator(context: try context())
        let parameter = try #require(node.inputNumber1.parameter as? FloatParameter)
        node.markClean()
        parameter.value = 4
        #expect(node.inputNumber1.value == 0)
        #expect(!node.isDirty)
    }

    @Test("A published inner port's edit invalidates the outer node through its proxy")
    func proxyInvalidatesOuterNode() throws {
        let context = try context()
        let innerGraph = Graph(context: context)
        let inner = NumberBinaryOperator(context: context)
        innerGraph.addNode(inner)
        innerGraph.setPublished(true, port: inner.inputNumber1)
        let outer = SubgraphNode(context: context, subGraph: innerGraph)
        inner.markClean()
        outer.markClean()
        inner.inputNumber1.value = 6
        #expect(inner.isDirty)
        #expect(outer.isDirty)
        #expect((outer.ports.first as? NodePort<Float>)?.value == 6)
    }

    @Test("A replacement parameter mirrors later port edits, which still invalidate")
    func replacementParameter() throws {
        let node = NumberBinaryOperator(context: try context())
        let original = try #require(node.inputNumber1.parameter as? FloatParameter)
        let replacement = FloatParameter("Replacement", 0)
        node.replaceParameterOfPort(node.inputNumber1, withParam: replacement)
        node.markClean()
        node.inputNumber1.value = 8
        #expect(replacement.value == 8)
        #expect(original.value == 0)
        #expect(node.isDirty)
    }

    @Test("A decoded node's port edits invalidate it")
    func decodedNodeInvalidates() throws {
        let context = try context()
        let data = try JSONEncoder().encode(NumberBinaryOperator(context: context))
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let node = try decoder.decode(NumberBinaryOperator.self, from: data)
        node.markClean()
        node.inputNumber1.value = 7
        #expect(node.isDirty)
    }
}
