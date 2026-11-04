import Testing
import Foundation
import Metal
import Satin
@testable import Fabric

/// A node that declares, while it holds one, a plain port carrying a parameter.
private final class PlainParameterPortNode: NumberBinaryOperator
{
    var plain: NodePort<Float>? { didSet { reconcilePorts() } }

    override func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + (plain.map { [PortDeclaration(key: "plain", port: $0)] } ?? [])
    }
}

@Suite("Node parameter observation", .serialized)
struct NodeParameterObservationTests {
    private func context() throws -> Context {
        Context(device: try #require(MTLCreateSystemDefaultDevice()), sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    @Test("Parameter-backed ports invalidate their node without extra Node subscriptions")
    func portOwnedObservation() throws {
        let node = NumberBinaryOperator(context: try context())
        #expect(node.inputParamCancellables.isEmpty)
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

    @Test("Standalone parameters retain Node observation")
    func standaloneParameter() throws {
        let node = NumberBinaryOperator(context: try context())
        let parameter = FloatParameter("Standalone", 0)
        node.parameterGroup.append(parameter)
        node.synchronizeParameters()
        #expect(node.inputParamCancellables.count == 1)
        node.markClean()
        parameter.value = 4
        #expect(node.isDirty)
    }

    @Test("Distinct parameters with the same UUID are not mistaken for the observed instance")
    func parameterIdentity() throws {
        let node = NumberBinaryOperator(context: try context())
        let parameter = FloatParameter("Standalone", 0)
        parameter.id = node.inputNumber1.id
        node.parameterGroup.append(parameter)
        node.synchronizeParameters()
        #expect(node.inputParamCancellables.count == 1)
        node.markClean()
        parameter.value = 4
        #expect(node.isDirty)
        #expect(node.inputNumber1.value == 0)
    }

    @Test("Published proxy parameters still invalidate their outer node")
    func proxyObservation() throws {
        let context = try context()
        let innerGraph = Graph(context: context)
        let inner = NumberBinaryOperator(context: context)
        innerGraph.addNode(inner)
        inner.inputNumber1.publishInGraph(true)
        innerGraph.rebuildPublishedParameterGroup()
        let outer = SubgraphNode(context: context, subGraph: innerGraph)
        #expect(outer.inputParamCancellables.count == 1)
        inner.markClean()
        outer.markClean()
        inner.inputNumber1.value = 6
        #expect(inner.isDirty)
        #expect(outer.isDirty)
        #expect((outer.ports.first as? NodePort<Float>)?.value == 6)
    }

    @Test("Declared plain ports with parameters receive Node observation")
    func dynamicPlainPort() throws {
        let node = PlainParameterPortNode(context: try context())
        let parameter = FloatParameter("Plain parameter", 0)
        let port = NodePort<Float>(name: "Plain", kind: .Inlet)
        port.parameter = parameter
        node.plain = port
        node.markClean()
        parameter.value = 5
        #expect(node.isDirty)
    }

    @Test("Removing a plain port cancels any obsolete Node observation")
    func removePlainPort() throws {
        let node = PlainParameterPortNode(context: try context())
        let parameter = FloatParameter("Plain parameter", 0)
        let port = NodePort<Float>(name: "Plain", kind: .Inlet)
        port.parameter = parameter
        node.plain = port
        node.synchronizeParameters()
        node.plain = nil
        node.markClean()
        parameter.value = 5
        #expect(!node.isDirty)
        #expect(node.inputParamCancellables.isEmpty)
    }

    @Test("Replacing parameters retires the old observer and preserves new changes", arguments: [false, true])
    func replaceParameter(parameterBacked: Bool) throws {
        let node = PlainParameterPortNode(context: try context())
        let port: Fabric.Port
        if parameterBacked {
            port = node.inputNumber1
        } else {
            let plain = NodePort<Float>(name: "Plain", kind: .Inlet)
            plain.parameter = FloatParameter("Original", 0)
            node.plain = plain
            port = plain
        }
        node.synchronizeParameters()
        let original = try #require(port.parameter as? FloatParameter)
        let replacement = FloatParameter("Replacement", 0)
        node.replaceParameterOfPort(port, withParam: replacement)
        node.markClean()
        original.value = 4
        #expect(!node.isDirty)
        node.markClean()
        if parameterBacked {
            node.inputNumber1.value = 8
            #expect(replacement.value == 8)
        } else {
            replacement.value = 8
        }
        #expect(node.isDirty)
        #expect(node.inputParamCancellables.count == (parameterBacked ? 0 : 1))
    }

    @Test("Decoded parameter ports invalidate their node without duplicate observers")
    func decodedObservation() throws {
        let context = try context()
        let data = try JSONEncoder().encode(NumberBinaryOperator(context: context))
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let node = try decoder.decode(NumberBinaryOperator.self, from: data)
        #expect(node.inputParamCancellables.isEmpty)
        node.markClean()
        let parameter = try #require(node.inputNumber1.parameter as? FloatParameter)
        node.inputNumber1.value = 7
        #expect(node.isDirty)
        #expect(parameter.value == 7)
    }
}
