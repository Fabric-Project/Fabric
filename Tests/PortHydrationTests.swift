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

    @Test("Hydration keeps the backing parameter on the port's identity")
    func hydrationKeepsParameterOnPortIdentity() throws
    {
        guard let context = makeContext() else { return }

        let node = NumberBinaryOperator(context: context)
        let savedID = node.inputNumber1.id
        #expect(node.inputNumber1.parameter?.id == savedID)

        let decoded = try roundTrip(node, context: context)

        #expect(decoded.inputNumber1.id == savedID)
        #expect(decoded.inputNumber1.parameter?.id == savedID)

        // Material syncs swap the backing parameter wholesale
        // (Node.replaceParameterOfPort); the invariant has to survive that too.
        let replacement = FloatParameter("Number 1", 3)
        decoded.replaceParameterOfPort(decoded.inputNumber1, withParam: replacement)

        #expect(decoded.inputNumber1.id == savedID)
        #expect(decoded.inputNumber1.parameter?.id == savedID)
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

    @Test("JavaScript node rebuilds its script ports on decode and keeps identity")
    @MainActor
    func javaScriptNodeRebuildsScriptPortsOnDecode() throws
    {
        guard let context = makeContext() else { return }

        let node = JavaScriptNode(context: context)
        node.updateScriptSource("""
            function (__number doubled) main(__number x) {
              return { doubled: x * 2 }
            }
            """)

        let inputPort = try #require(node.findPort(named: "x") as Fabric.Port?)
        let outputPort = try #require(node.findPort(named: "doubled") as Fabric.Port?)
        inputPort.published = true
        let savedInputID = inputPort.id
        let savedOutputID = outputPort.id

        let decoded = try roundTrip(node, context: context)

        #expect((decoded.findPort(named: "x") as Fabric.Port?)?.id == savedInputID)
        #expect((decoded.findPort(named: "x") as Fabric.Port?)?.published == true)
        #expect((decoded.findPort(named: "doubled") as Fabric.Port?)?.id == savedOutputID)
        #expect(decoded.droppedPortStateKeys.isEmpty)
    }

    @Test("Live Image node rebuilds its saved shader's uniform ports on decode")
    @MainActor
    func liveImageNodeRebuildsSavedShaderUniformPortsOnDecode() throws
    {
        guard let context = makeContext() else { return }

        let node = LiveImageNode(context: context)
        node.updateShaderSource("""
            #include <metal_stdlib>
            using namespace metal;

            typedef struct {
                float amount; // slider, 0.0, 1.0, 1.0, Amount
                float gain; // slider, 0.0, 2.0, 0.5, Gain
            } PostUniforms;

            fragment half4 postFragment(VertexData in [[stage_in]],
                                        constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                                        texture2d<half, access::sample> inputTexture [[texture(FragmentTextureCustom0)]]) {
                constexpr sampler s(address::clamp_to_edge, filter::linear);
                half4 color = inputTexture.sample(s, in.texcoord);
                return mix(half4(0.0), color * half(uniforms.gain), half(uniforms.amount));
            }
            """)

        // The declared uniform port must exist before the round trip, or the
        // test would only prove the template shader's ports survive.
        let gainPort = try #require(node.findPort(named: "Gain") as? ParameterPort<Float>)
        gainPort.value = 1.7
        let savedGainID = gainPort.id
        let savedImageInputID = try #require((node.findPort(named: "Image") as Fabric.Port?)?.id)

        let decoded = try roundTrip(node, context: context)

        let decodedGain = try #require(decoded.findPort(named: "Gain") as? ParameterPort<Float>)
        #expect(decodedGain.id == savedGainID)
        #expect(decodedGain.value == 1.7)
        #expect((decoded.findPort(named: "Image") as Fabric.Port?)?.id == savedImageInputID)
        #expect(decoded.droppedPortStateKeys.isEmpty)
    }

    @Test("Compute processor node rebuilds its processor and uniform ports on decode")
    func computeProcessorNodeRebuildsProcessorOnDecode() throws
    {
        guard let context = makeContext() else { return }

        // Resolve the shader through the registry wrapper so the test follows
        // the same path a document's node class resolution does.
        let wrapper = try #require(try NodeRegistry.shared.availableNodes.first {
            $0.nodeClass == BaseTextureComputeProcessorNode.self
        })
        let fileURL = try #require(wrapper.fileURL)

        let node = try BaseTextureComputeProcessorNode(context: context, fileURL: fileURL)
        let savedPortIDs = node.ports.map(\.id)
        let savedDisplayName = node.displayName

        let decoded = try roundTrip(node, context: context)

        #expect(decoded.compute != nil)
        #expect(decoded.displayName == savedDisplayName)
        #expect(decoded.ports.map(\.id) == savedPortIDs)
        #expect(decoded.droppedPortStateKeys.isEmpty)
    }

    @Test("Game controller ports persist as descriptors and rebuild on decode")
    func gameControllerPortsRebuildFromDescriptors() throws
    {
        guard let context = makeContext() else { return }

        // No controller is present in tests; adding the ports directly stands
        // in for what a connected profile does via synchronizePorts.
        let node = GameControllerNode(context: context)
        node.addDynamicPort(NodePort<Float>(name: "Left Stick X", kind: .Outlet))
        node.addDynamicPort(NodePort<Bool>(name: "A", kind: .Outlet))
        let savedPortIDs = node.ports.map(\.id)

        let decoded = try roundTrip(node, context: context)

        #expect(decoded.ports.map(\.id) == savedPortIDs)
        #expect(decoded.findPort(named: "Left Stick X") is NodePort<Float>)
        #expect(decoded.findPort(named: "A") is NodePort<Bool>)
        #expect(decoded.droppedPortStateKeys.isEmpty)
    }

    @Test("Ports added after graph decode cannot resurrect stale snapshot state")
    func latePortsDoNotResurrectStaleSnapshotState() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let node = NumberBinaryOperator(context: context)
        graph.addNode(node)

        // Retire a key in the saved document, then load: the state is
        // reported dropped and the node's hydration window closes.
        let data = try JSONEncoder().encode(graph)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var nodeMap = try #require(object["nodeMap"] as? [[String: Any]])
        var value = try #require(nodeMap[0]["value"] as? [String: Any])
        var ports = try #require(value["ports"] as? [[String: Any]])
        ports[0]["name"] = "retiredKey"
        let retiredSnapshotID = try #require((ports[0]["payload"] as? [String: Any])
            .flatMap { ($0["base"] as? [String: Any])?["id"] as? String })
        value["ports"] = ports
        nodeMap[0]["value"] = value
        object["nodeMap"] = nodeMap

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        let decoded = try decoder.decode(Graph.self, from: try JSONSerialization.data(withJSONObject: object))

        #expect(decoded.droppedPortStateDiagnostics.first?.droppedRegistryKeys == ["retiredKey"])

        // The pre-session failure mode: state lingered after decode, so a
        // port registered under the stale key months later — a settings
        // toggle, a reconnecting device — suddenly adopted the saved identity
        // without its wires. The window is closed now; late ports are fresh.
        let decodedNode = try #require(decoded.nodes.first { $0.id == node.id })
        let latePort = NodePort<Float>(name: "Retired", kind: .Inlet)
        decodedNode.addDynamicPort(latePort, name: "retiredKey")

        #expect(latePort.id.uuidString != retiredSnapshotID)
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
