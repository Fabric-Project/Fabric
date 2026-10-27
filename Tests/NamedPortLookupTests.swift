import Testing
import Foundation
import Metal
import Satin
import Fabric

@Suite("Named port lookup", .serialized)
struct NamedPortLookupTests {
    private func context() throws -> Context {
        Context(device: try #require(MTLCreateSystemDefaultDevice()), sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    @Test("Removing an earlier port preserves every remaining named lookup")
    func removal() throws {
        let node = NumberBinaryOperator(context: try context())
        let second = node.inputNumber2
        let operation = node.inputParam
        let output = node.outputNumber
        node.removePort(node.inputNumber1)
        #expect(node.findPort(named: "inputNumber1", as: ParameterPort<Float>.self) == nil)
        #expect(node.inputNumber2 === second)
        #expect(node.inputParam === operation)
        #expect(node.outputNumber === output)
    }

    @Test("Reordering preserves registry keys that differ from display names")
    func reorder() throws {
        let node = NumberBinaryOperator(context: try context())
        let first = node.inputNumber1
        let operation = node.inputParam
        let output = node.outputNumber
        node.reorderPorts(Array(node.ports.reversed()))
        #expect(node.ports.first === output)
        #expect(node.inputNumber1 === first)
        #expect(node.inputParam === operation)
        #expect(node.outputNumber === output)
        node.removePort(operation)
        #expect(node.findPort(named: "inputParam", as: ParameterPort<String>.self) == nil)
        #expect(node.inputNumber1 === first)
        #expect(node.outputNumber === output)
    }

    @Test("Replacing a port preserves its key and releases the retired instance")
    func replacement() throws {
        let node = NumberBinaryOperator(context: try context())
        weak var retired: Fabric.Port?
        do {
            let original = node.inputNumber1
            retired = original
            let replacement = ParameterPort(parameter: FloatParameter("New Number", 7), id: original.id)
            node.replacePort(original, with: replacement)
        }
        #expect(retired == nil)
        #expect(node.inputNumber1.value == 7)
        #expect(node.inputNumber2.value == 0)
    }

    @Test("An earlier public port array remains a snapshot across registry edits")
    func arraySnapshot() throws {
        let node = NumberBinaryOperator(context: try context())
        let snapshot = node.ports
        let original = node.inputNumber1
        node.removePort(original)
        #expect(snapshot.count == 4)
        #expect(snapshot.first === original)
        #expect(node.ports.count == 3)
        #expect(node.ports.first === node.inputNumber2)
        let added = NodePort<Float>(name: "Added", kind: .Inlet)
        node.addDynamicPort(added, name: "newInput")
        #expect(node.findPort(named: "newInput", as: NodePort<Float>.self) === added)
        #expect(snapshot.last === node.outputNumber)
    }

    @Test("Removing an older duplicate name preserves its most recent registration")
    func duplicateName() throws {
        let node = NumberBinaryOperator(context: try context())
        let original = node.inputNumber1
        let replacement = ParameterPort(parameter: FloatParameter("Latest", 9))
        node.addDynamicPort(replacement, name: "inputNumber1")
        #expect(node.inputNumber1 === replacement)
        node.removePort(original)
        #expect(node.inputNumber1 === replacement)
        #expect(node.inputParam.value == "Add")
        node.removePort(replacement)
        #expect(node.findPort(named: "inputNumber1", as: ParameterPort<Float>.self) == nil)
    }

    @Test("Edited registry keys round-trip with their values and port identities")
    func roundTrip() throws {
        let context = try context()
        let node = NumberBinaryOperator(context: context)
        let replacement = ParameterPort(parameter: FloatParameter("Replacement", 12), id: node.inputNumber1.id)
        node.replacePort(node.inputNumber1, with: replacement)
        node.reorderPorts(Array(node.ports.reversed()))
        let data = try JSONEncoder().encode(node)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(NumberBinaryOperator.self, from: data)
        #expect(decoded.inputNumber1.value == 12)
        #expect(decoded.inputNumber1.id == replacement.id)
        #expect(decoded.inputParam.id == node.inputParam.id)
        #expect(decoded.outputNumber.id == node.outputNumber.id)
    }
}
