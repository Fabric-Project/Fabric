import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// Node-level round trips through the declare-then-hydrate decode (see
/// Node.init(from:)): the port set comes from the code, the document
/// contributes only the state it owns — identity, published state, value.
@Suite("Port Hydration")
struct PortHydrationTests
{
    private func makeContext() -> Context?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
    }

    private func roundTrip<N: Node>(_ node: N, context: Context, editJSON: ((inout [String: Any]) -> Void)? = nil) throws -> N
    {
        let data = try JSONEncoder().encode(node)

        var encodedData = data
        if let editJSON
        {
            var jsonObject = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            editJSON(&jsonObject)
            encodedData = try JSONSerialization.data(withJSONObject: jsonObject)
        }

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        return try decoder.decode(N.self, from: encodedData)
    }

    @Test("Round trip preserves port identity, published state and values")
    func roundTripPreservesDocumentOwnedState() throws
    {
        guard let context = makeContext() else { return }

        let node = NumberBinaryOperator(context: context)
        node.inputNumber1.value = 72
        node.inputNumber2.published = true
        node.inputNumber2.publishedName = "Custom Name"

        let savedIDs = node.ports.map(\.id)

        let decoded = try roundTrip(node, context: context)

        #expect(decoded.ports.map(\.id) == savedIDs)
        #expect(decoded.inputNumber1.value == 72)
        #expect(decoded.inputNumber2.published)
        #expect(decoded.inputNumber2.publishedName == "Custom Name")
        #expect(decoded.droppedPortStateKeys.isEmpty)
    }

    @Test("Dynamic strategy ports rebuild from the decoded strategy and keep identity")
    func dynamicPortsKeepIdentity() throws
    {
        guard let context = makeContext() else { return }

        let node = SampleAndHoldNode(context: context, portType: .Float)
        let savedInputID = try #require((node.findPort(named: "inputValue") as Fabric.Port?)?.id)
        let savedOutputID = try #require((node.findPort(named: "outputValue") as Fabric.Port?)?.id)

        let decoded = try roundTrip(node, context: context)

        #expect(decoded.selectedPortType == .Float)
        #expect((decoded.findPort(named: "inputValue") as Fabric.Port?)?.id == savedInputID)
        #expect((decoded.findPort(named: "outputValue") as Fabric.Port?)?.id == savedOutputID)
        #expect(decoded.droppedPortStateKeys.isEmpty)
    }

    @Test("Retired port state is dropped and reported, not resurrected")
    func retiredPortStateIsDroppedAndReported() throws
    {
        guard let context = makeContext() else { return }

        let node = NumberBinaryOperator(context: context)
        let declaredPortCount = node.ports.count

        // Rewrite one snapshot's registry key to one no code declares —
        // exactly what a document written by an older build holds after the
        // code retires or re-keys a port.
        let decoded = try roundTrip(node, context: context) { jsonObject in
            var ports = jsonObject["ports"] as? [[String: Any]] ?? []
            if var first = ports.first
            {
                first["name"] = "retiredKey"
                ports[0] = first
            }
            jsonObject["ports"] = ports
        }

        #expect(decoded.ports.count == declaredPortCount)
        #expect((decoded.findPort(named: "retiredKey") as Fabric.Port?) == nil)
        #expect(decoded.droppedPortStateKeys == ["retiredKey"])
    }

    @Test("Declared parameter metadata wins over the document's copy")
    func declaredParameterMetadataWins() throws
    {
        guard let context = makeContext() else { return }

        // Model an old document: the parameter's range was different when saved.
        let node = NumberBinaryOperator(context: context)
        node.inputNumber1.value = 5
        let declaredParameter = try #require(node.inputNumber1.parameter as? FloatParameter)
        let declaredMin = declaredParameter.min
        let declaredMax = declaredParameter.max
        declaredParameter.min = -999
        declaredParameter.max = 999

        let decoded = try roundTrip(node, context: context)
        let decodedParameter = try #require(decoded.inputNumber1.parameter as? FloatParameter)

        #expect(decodedParameter.min == declaredMin)
        #expect(decodedParameter.max == declaredMax)
        #expect(decoded.inputNumber1.value == 5)
    }

    @Test("Legacy registry keys hydrate through declared aliases")
    func legacyKeysHydrateThroughAliases() throws
    {
        guard let context = makeContext() else { return }

        let node = AliasedPortNode(context: context)
        node.input.value = 7
        let savedID = node.input.id

        // Rewrite the snapshot to the pre-rename key; the alias declared by
        // the node must route its state onto today's port.
        let decoded = try roundTrip(node, context: context) { jsonObject in
            var ports = jsonObject["ports"] as? [[String: Any]] ?? []
            for index in ports.indices where ports[index]["name"] as? String == "input"
            {
                ports[index]["name"] = "legacyInput"
            }
            jsonObject["ports"] = ports
        }

        // Plain NodePort values are not persisted; identity is the contract here.
        #expect(decoded.input.id == savedID)
        #expect(decoded.droppedPortStateKeys.isEmpty)
    }
}

private final class AliasedPortNode: Node
{
    override class var name: String { "Aliased Port" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Test node with a renamed port key." }

    var input: NodePort<Float> { port(named: "input") }

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [
            ("input", NodePort<Float>(name: "Input", kind: .Inlet)),
        ]
    }

    override class func legacyPortStateKeys(forRegistryKey registryKey: String) -> [String]
    {
        registryKey == "input" ? ["legacyInput"] : []
    }
}
