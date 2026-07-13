import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

private struct DictionaryTestHarness
{
    let context: Context
    let renderer: GraphRenderer

    init?()
    {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }

        self.context = Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
        self.renderer = GraphRenderer(context: self.context)
    }

    func execute(_ node: Node) throws
    {
        let descriptor = MTLRenderPassDescriptor()
        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            throw DictionaryTestFailure("Failed to create command buffer")
        }

        node.execute(
            renderer: renderer,
            executionInfo: GraphExecutionInfo(
                timing: GraphExecutionTiming(
                    time: 0,
                    deltaTime: 0,
                    displayTime: 0,
                    systemTime: 0,
                    frameNumber: 0
                ),
                iterationInfo: nil,
                eventInfo: nil
            ),
            renderPassDescriptor: descriptor,
            commandBuffer: commandBuffer
        )
    }
}

private struct DictionaryTestFailure: Error, CustomStringConvertible
{
    let description: String

    init(_ description: String)
    {
        self.description = description
    }
}

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

    @Test("Typed dictionaries box and unbox through PortValue")
    func typedDictionariesBoxAndUnboxThroughPortValue() throws
    {
        let dictionary: Dictionary<String, Float> = ["width": 1920, "height": 1080]
        let boxed = dictionary.toPortValue()

        guard case .Dictionary(let boxedValues) = boxed else {
            throw DictionaryTestFailure("Expected boxed dictionary")
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
        guard let harness = DictionaryTestHarness() else { return }

        let node = DictionaryFromJSONStringNode(context: harness.context)
        node.inputJSONString.value = #"{"name":"Fabric","enabled":true,"size":3,"nested":{"value":1},"items":[1,"two",null]}"#

        try harness.execute(node)

        guard case .Dictionary(let dictionary) = node.outputDictionary.snapshotValue() else {
            throw DictionaryTestFailure("Expected parsed dictionary")
        }

        #expect(dictionary["name"] == .String("Fabric"))
        #expect(dictionary["enabled"] == .Bool(true))
        #expect(dictionary["size"] == .Float(3))

        guard case .Dictionary(let nested)? = dictionary["nested"] else {
            throw DictionaryTestFailure("Expected nested dictionary")
        }
        #expect(nested["value"] == .Float(1))

        guard case .Array(let items)? = dictionary["items"] else {
            throw DictionaryTestFailure("Expected array")
        }
        #expect(items.count == 2)
        #expect(node.outputValid.value == true)
        #expect(node.outputError.value == "")
    }

    @Test("Dictionary from keys and values creates typed dictionary")
    func dictionaryFromKeysAndValuesCreatesTypedDictionary() throws
    {
        guard let harness = DictionaryTestHarness() else { return }

        let node = DictionaryFromKeysAndValuesNode(context: harness.context, portType: .Float)
        let inputKeys: Fabric.Port = node.port(named: "inputKeys")
        let inputValues: Fabric.Port = node.port(named: "inputValues")
        let outputDictionary: Fabric.Port = node.port(named: "outputDictionary")

        inputKeys.restoreValue(from: PortValue.Array(ContiguousArray([PortValue.String("x"), PortValue.String("y")])))
        inputValues.restoreValue(from: PortValue.Array(ContiguousArray([PortValue.Float(10), PortValue.Float(20)])))

        try harness.execute(node)

        guard case .Dictionary(let dictionary) = outputDictionary.snapshotValue() else {
            throw DictionaryTestFailure("Expected output dictionary")
        }

        #expect(outputDictionary.portType == PortType.Dictionary(valueType: .Float))
        #expect(dictionary["x"] == PortValue.Float(10))
        #expect(dictionary["y"] == PortValue.Float(20))
    }
}
