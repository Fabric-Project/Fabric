import Testing
import Foundation
import Metal
import Satin
@testable import Fabric

/// A Number Binary Operator whose interface can lose a port, run in another
/// order, or retype a port, through its declarations: the edits the registry's
/// key index has to follow.
private final class EditableOperatorNode: NumberBinaryOperator
{
    var omitted: Set<String> = [] { didSet { reconcilePorts() } }
    var reversed = false { didSet { reconcilePorts() } }
    var retypedFirstInput = false { didSet { reconcilePorts() } }

    override func declaredPorts() -> [PortDeclaration]
    {
        var declarations = super.declaredPorts().filter { declaration in
            guard case .own(let key) = declaration.key else { return true }
            return !omitted.contains(key)
        }
        if retypedFirstInput, let index = declarations.firstIndex(where: { $0.key == .own("inputNumber1") })
        {
            declarations[index] = PortDeclaration(key: "inputNumber1", portType: .Int, kind: .Inlet, name: "Integer")
        }
        return reversed ? declarations.reversed() : declarations
    }
}

@Suite("Named port lookup", .serialized)
struct NamedPortLookupTests {
    private func context() throws -> Context {
        Context(device: try #require(MTLCreateSystemDefaultDevice()), sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    @Test("Removing an earlier port preserves every remaining named lookup")
    func removal() throws {
        let node = EditableOperatorNode(context: try context())
        let second = node.inputNumber2
        let operation = node.inputParam
        let output = node.outputNumber
        node.omitted = ["inputNumber1"]
        #expect(node.findPort(named: "inputNumber1", as: ParameterPort<Float>.self) == nil)
        #expect(node.inputNumber2 === second)
        #expect(node.inputParam === operation)
        #expect(node.outputNumber === output)
    }

    @Test("Reordering preserves registry keys that differ from display names")
    func reorder() throws {
        let node = EditableOperatorNode(context: try context())
        let first = node.inputNumber1
        let operation = node.inputParam
        let output = node.outputNumber
        node.reversed = true
        #expect(node.ports.first === output)
        #expect(node.inputNumber1 === first)
        #expect(node.inputParam === operation)
        #expect(node.outputNumber === output)
        node.omitted = ["inputParam"]
        #expect(node.findPort(named: "inputParam", as: ParameterPort<String>.self) == nil)
        #expect(node.inputNumber1 === first)
        #expect(node.outputNumber === output)
    }

    @Test("Retyping a port keeps its key and releases the retired instance")
    func retype() throws {
        let node = EditableOperatorNode(context: try context())
        let originalID = node.inputNumber1.id
        node.retypedFirstInput = true
        #expect(node.findPort(named: "inputNumber1", as: ParameterPort<Int>.self)?.id == originalID)
        #expect(node.inputNumber2.value == 0)

        // The stored Float port is the node's own; the Int one only the
        // registry held, so retyping back lets it go.
        weak var retired: Fabric.Port?
        do {
            retired = node.findPort(named: "inputNumber1", as: ParameterPort<Int>.self)
            node.retypedFirstInput = false
        }
        #expect(retired == nil)
        #expect(node.findPort(named: "inputNumber1", as: ParameterPort<Float>.self) === node.inputNumber1)
    }

    @Test("An earlier public port array remains a snapshot across registry edits")
    func arraySnapshot() throws {
        let node = EditableOperatorNode(context: try context())
        let snapshot = node.ports
        let original = node.inputNumber1
        node.omitted = ["inputNumber1"]
        #expect(snapshot.count == 4)
        #expect(snapshot.first === original)
        #expect(node.ports.count == 3)
        #expect(node.ports.first === node.inputNumber2)
        #expect(snapshot.last === node.outputNumber)
    }

    @Test("A key declared twice is the first declaration's port")
    func duplicateKey() throws {
        final class DuplicateNode: NumberBinaryOperator {
            override func declaredPorts() -> [PortDeclaration] {
                super.declaredPorts() + [PortDeclaration(key: "inputNumber1", port: ParameterPort(parameter: FloatParameter("Latest", 9)))]
            }
        }
        let node = DuplicateNode(context: try context())
        #expect(node.ports.count == 4)
        #expect(node.inputNumber1.name == "Number A")
        #expect(node.inputParam.value == "Add")
    }

    @Test("Edited registry keys round-trip with their values")
    func roundTrip() throws {
        let context = try context()
        let node = EditableOperatorNode(context: context)
        node.inputNumber1.value = 12
        node.reversed = true
        let data = try JSONEncoder().encode(node)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(EditableOperatorNode.self, from: data)
        #expect(decoded.inputNumber1.value == 12)
        #expect(decoded.ports.first === decoded.inputNumber1)
    }
}
