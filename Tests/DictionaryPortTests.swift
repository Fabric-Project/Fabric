import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

@Suite("Dictionary Ports")
struct DictionaryPortTests
{
    @Test("Dictionary PortType raw values round trip recursively")
    func dictionaryPortTypeRawValuesRoundTripRecursively() throws
    {
        let types: [PortType] = [
            .Dictionary(valueType: .Float),
            .Dictionary(valueType: .Array(portType: .String)),
            .Dictionary(valueType: .Dictionary(valueType: .Virtual)),
            .Array(portType: .Dictionary(valueType: .Array(portType: .Float))),
        ]

        for type in types
        {
            #expect(PortType(rawValue: type.rawValue) == type)
        }
    }

    @Test("Array basics expose scalar element strategies")
    func arrayBasicsExposeScalarElementStrategies() throws
    {
        let options = ArrayCountNode.strategyOptions.compactMap { PortType(rawValue: $0.rawValue) }

        #expect(options.first == .Virtual)
        #expect(options.contains(.Float))
        #expect(options.contains(.String))
        #expect(!options.contains(.Array(portType: .Float)))
        #expect(!options.contains(.Dictionary(valueType: .Float)))
        #expect(!options.contains(.Array(portType: .Dictionary(valueType: .Virtual))))
    }

    @Test("Array virtual ports accept only array connections")
    func arrayVirtualPortsAcceptOnlyArrayConnections() throws
    {
        let arrayVirtual = PortType.Array(portType: .Virtual)

        #expect(arrayVirtual.canConnect(to: .Array(portType: .Float)))
        #expect(arrayVirtual.canConnect(to: .Array(portType: .Dictionary(valueType: .Array(portType: .Float)))))
        #expect(!arrayVirtual.canConnect(to: .Float))
        #expect(!PortType.Float.canConnect(to: arrayVirtual))
    }

    @Test("Legacy virtual array dynamic ports preserve identity when migrated")
    func legacyVirtualArrayDynamicPortsPreserveIdentityWhenMigrated() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let node = ArrayIndexValueNode(context: harness.context, portType: .Virtual)
        let currentInput: Fabric.Port = node.port(named: "inputPort")
        let legacyID = currentInput.id

        node.removePort(currentInput)

        let legacyInput = PortType.Virtual.makeFreshPort(
            name: "Array",
            kind: .Inlet,
            description: "Input array to index into",
            id: legacyID
        )
        legacyInput.published = true
        legacyInput.publishedName = "Legacy Array"
        node.addDynamicPort(legacyInput, name: "inputPort")

        node.rebuildPorts(forStrategy: PortType.Virtual.rawValue)

        let migratedInput: Fabric.Port = node.port(named: "inputPort")
        #expect(migratedInput.id == legacyID)
        #expect(migratedInput.portType == .Array(portType: .Virtual))
        #expect(migratedInput.published)
        #expect(migratedInput.publishedName == "Legacy Array")
    }

    @Test("Typed dictionaries box and unbox through PortValue")
    func typedDictionariesBoxAndUnboxThroughPortValue() throws
    {
        let dictionary: Dictionary<String, Float> = ["width": 1920, "height": 1080]
        let boxed = dictionary.toPortValue()

        guard case .Dictionary(let boxedValues) = boxed else {
            throw GraphExecutionTestFailure("Expected boxed dictionary")
        }

        #expect(boxedValues["width"] == .Float(1920))
        #expect(boxedValues["height"] == .Float(1080))
        #expect(Dictionary<String, Float>.fromPortValue(boxed) == dictionary)
    }

    @Test("Nested dictionary ports preserve declared recursive PortType through AnyPort")
    func nestedDictionaryPortsPreserveDeclaredRecursivePortTypeThroughAnyPort() throws
    {
        let portType: PortType = .Dictionary(valueType: .Dictionary(valueType: .Float))
        let port = portType.makeFreshPort(name: "Dictionary", kind: .Outlet)

        #expect(port.portType == portType)

        let data = try JSONEncoder().encode(AnyPort(port))
        let decoded = try JSONDecoder().decode(AnyPort.self, from: data).base

        #expect(decoded.portType == portType)
    }

    @Test("JSON parser outputs boxed virtual dictionary")
    func jsonParserOutputsBoxedVirtualDictionary() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let node = DictionaryFromJSONStringNode(context: harness.context)
        node.inputJSONString.value = #"{"name":"Fabric","enabled":true,"size":3,"nested":{"value":1},"items":[1,"two",null]}"#

        try harness.execute(node)

        guard case .Dictionary(let dictionary) = node.outputDictionary.snapshotValue() else {
            throw GraphExecutionTestFailure("Expected parsed dictionary")
        }

        #expect(dictionary["name"] == .String("Fabric"))
        #expect(dictionary["enabled"] == .Bool(true))
        #expect(dictionary["size"] == .Float(3))

        guard case .Dictionary(let nested)? = dictionary["nested"] else {
            throw GraphExecutionTestFailure("Expected nested dictionary")
        }
        #expect(nested["value"] == .Float(1))

        guard case .Array(let items)? = dictionary["items"] else {
            throw GraphExecutionTestFailure("Expected array")
        }
        #expect(items.count == 2)
        #expect(node.outputValid.value == true)
        #expect(node.outputError.value == "")
    }

    @Test("Compose Dictionary creates typed dictionary")
    func composeDictionaryCreatesTypedDictionary() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let node = ComposeDictionaryNode(context: harness.context, portType: .Float)
        let inputKeys: Fabric.Port = node.port(named: "inputKeys")
        let inputValues: Fabric.Port = node.port(named: "inputValues")
        let outputDictionary: Fabric.Port = node.port(named: "outputDictionary")

        inputKeys.restoreValue(from: PortValue.Array(ContiguousArray([PortValue.String("x"), PortValue.String("y")])))
        inputValues.restoreValue(from: PortValue.Array(ContiguousArray([PortValue.Float(10), PortValue.Float(20)])))

        try harness.execute(node)

        guard case .Dictionary(let dictionary) = outputDictionary.snapshotValue() else {
            throw GraphExecutionTestFailure("Expected output dictionary")
        }

        #expect(outputDictionary.portType == PortType.Dictionary(valueType: .Float))
        #expect(dictionary["x"] == PortValue.Float(10))
        #expect(dictionary["y"] == PortValue.Float(20))
    }

    @Test("Decompose Dictionary outputs sorted keys and values")
    func decomposeDictionaryOutputsSortedKeysAndValues() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let node = DecomposeDictionaryNode(context: harness.context, portType: .Float)
        let inputDictionary: Fabric.Port = node.port(named: "inputDictionary")
        let outputKeys: Fabric.Port = node.port(named: "outputKeys")
        let outputValues: Fabric.Port = node.port(named: "outputValues")

        inputDictionary.restoreValue(from: PortValue.Dictionary([
            "y": .Float(20),
            "x": .Float(10),
        ]))

        try harness.execute(node)

        guard case .Array(let keys) = outputKeys.snapshotValue() else {
            throw GraphExecutionTestFailure("Expected output keys")
        }
        guard case .Array(let values) = outputValues.snapshotValue() else {
            throw GraphExecutionTestFailure("Expected output values")
        }

        #expect(outputKeys.portType == PortType.Array(portType: .String))
        #expect(outputValues.portType == PortType.Array(portType: .Float))
        #expect(keys == [.String("x"), .String("y")])
        #expect(values == [.Float(10), .Float(20)])
    }
}
