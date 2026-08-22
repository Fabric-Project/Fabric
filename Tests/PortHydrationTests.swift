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

    /// Saves `graph`, rewrites one node's encoded form, and loads the result —
    /// the way a document written by a working build is opened after the source
    /// a node rebuilds itself from has gone bad.
    private func roundTripGraph(_ graph: Graph,
                                context: Context,
                                editingNode nodeID: UUID,
                                editJSON: (inout [String: Any]) -> Void) throws -> Graph
    {
        let data = try JSONEncoder().encode(graph)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var nodeMap = try #require(object["nodeMap"] as? [[String: Any]])

        let index = try #require(nodeMap.firstIndex {
            ($0["value"] as? [String: Any])?["id"] as? String == nodeID.uuidString
        })
        var value = try #require(nodeMap[index]["value"] as? [String: Any])
        editJSON(&value)
        nodeMap[index]["value"] = value
        object["nodeMap"] = nodeMap

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        return try decoder.decode(Graph.self, from: try JSONSerialization.data(withJSONObject: object))
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

    @Test("A JavaScript node whose saved script no longer parses keeps its ports and wires")
    @MainActor
    func javaScriptNodeKeepsPortsWhenSavedScriptFailsToParse() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let node = JavaScriptNode(context: context)
        let consumer = NumberBinaryOperator(context: context)
        graph.addNode(node)
        graph.addNode(consumer)

        node.updateScriptSource("""
            function (__number doubled) main(__number x) {
              return { doubled: x * 2 }
            }
            """)

        let outputPort = try #require(node.findPort(named: "doubled") as Fabric.Port?)
        outputPort.connect(to: consumer.inputNumber1)

        let savedPortIDs = node.ports.map(\.id)
        #expect(savedPortIDs.count == 2)

        let decodedGraph = try roundTripGraph(graph, context: context, editingNode: node.id) { value in
            value["scriptSource"] = "function (this is not javascript"
        }

        let decodedNode = try #require(decodedGraph.nodes.first { $0.id == node.id } as? JavaScriptNode)

        #expect(decodedNode.ports.map(\.id) == savedPortIDs)
        #expect(decodedGraph.droppedPortStateDiagnostics.isEmpty)
        #expect(decodedGraph.droppedConnectionDiagnostics.isEmpty)
        #expect(try #require(decodedNode.findPort(named: "doubled") as Fabric.Port?).connections.count == 1)
    }

    @Test("A Live Image node whose saved shader no longer compiles keeps its ports and wires")
    @MainActor
    func liveImageNodeKeepsPortsWhenSavedShaderFailsToCompile() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let node = LiveImageNode(context: context)
        let source = NumberBinaryOperator(context: context)
        graph.addNode(node)
        graph.addNode(source)

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

        let gainPort = try #require(node.findPort(named: "Gain") as? ParameterPort<Float>)
        gainPort.value = 1.7
        source.outputNumber.connect(to: gainPort)

        let savedPortIDs = node.ports.map(\.id)

        // updateShaderSource writes and recompiles, so the broken source has to
        // reach the node through the document. The node id has to change with
        // it: the shader workspace is keyed on that id, and reusing it would
        // have the decoded node recompile a directory this test already
        // compiled a working shader in.
        let decodedNodeID = UUID()
        let decodedGraph = try roundTripGraph(graph, context: context, editingNode: node.id) { value in
            value["shaderSource"] = "this is not a metal shader"
            value["id"] = decodedNodeID.uuidString
        }

        let decodedNode = try #require(decodedGraph.nodes.first { $0.id == decodedNodeID } as? LiveImageNode)

        #expect(decodedNode.currentShaderErrorDescription() != nil)
        #expect(Set(decodedNode.ports.map(\.id)) == Set(savedPortIDs))
        #expect(decodedGraph.droppedPortStateDiagnostics.isEmpty)
        #expect(decodedGraph.droppedConnectionDiagnostics.isEmpty)

        let decodedGain = try #require(decodedNode.findPort(named: "Gain") as? ParameterPort<Float>)
        #expect(decodedGain.value == 1.7)
        #expect(decodedGain.connections.count == 1)
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

    @Test("A compute node keeps its shader binding when the bundle no longer provides the file")
    func computeProcessorNodeKeepsUnresolvableEffectPath() throws
    {
        guard let context = makeContext() else { return }

        let wrapper = try #require(try NodeRegistry.shared.availableNodes.first {
            $0.nodeClass == BaseTextureComputeProcessorNode.self
        })
        let node = try BaseTextureComputeProcessorNode(context: context, fileURL: try #require(wrapper.fileURL))

        let retiredPath = "Effects/Compute/RetiredEffect.metal"
        let decoded = try roundTrip(node, context: context) { jsonObject in
            jsonObject["effectPath"] = retiredPath
        }

        let reencoded = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        #expect(reencoded["effectPath"] as? String == retiredPath)
        #expect(decoded.compute == nil)
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

    @Test("Game controller reconnect record survives a save with no controller attached")
    func gameControllerSavedInfoSurvivesSaveWithoutHardware() throws
    {
        guard let context = makeContext() else { return }

        let node = GameControllerNode(context: context)

        // Stand in for a document saved while the controller was plugged in;
        // no hardware is present in tests, so the record can only be injected.
        let savedInfo: [String: Any] = ["id": "Vendor_Extended Gamepad_0",
                                        "displayName": "Vendor",
                                        "vendorName": "Vendor",
                                        "productCategory": "Extended Gamepad"]

        let decoded = try roundTrip(node, context: context) { jsonObject in
            jsonObject["selectedControllerID"] = savedInfo["id"]
            jsonObject["savedControllerInfo"] = savedInfo
        }

        let reencoded = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        let reencodedInfo = try #require(reencoded["savedControllerInfo"] as? [String: Any])

        #expect(reencodedInfo["id"] as? String == savedInfo["id"] as? String)
        #expect(reencodedInfo["productCategory"] as? String == savedInfo["productCategory"] as? String)
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

    @Test("A port removed and recreated within one decode keeps its identity")
    func removeAndRecreateWithinDecodeKeepsIdentity() throws
    {
        guard let context = makeContext() else { return }

        let node = RecreatingPortNode(context: context)
        let savedID = node.value.id

        let decoded = try roundTrip(node, context: context)

        #expect(decoded.value.id == savedID)
        #expect(decoded.droppedPortStateKeys.isEmpty)
    }

    @Test("Duplicating a node closes its hydration window")
    func duplicatingANodeClosesItsHydrationWindow() throws
    {
        guard let context = makeContext() else { return }

        let graph = Graph(context: context)
        let node = NumberBinaryOperator(context: context)
        graph.addNode(node)

        // A key no registerPorts declares: it survives the duplicate's encode
        // and has nothing to hydrate on the way back in, so it is exactly the
        // stale state a later port must not pick up.
        node.addDynamicPort(NodePort<Float>(name: "Extra", kind: .Inlet), name: "extraKey")

        let duplicated = try #require(graph.duplicateNodes([node]).first)

        let latePort = NodePort<Float>(name: "Extra", kind: .Inlet)
        let freshID = latePort.id
        duplicated.addDynamicPort(latePort, name: "extraKey")

        #expect(latePort.id == freshID)
    }

    @Test("State under a key the code no longer declares drops and is reported")
    func retiredKeyStateDropsAndReports() throws
    {
        guard let context = makeContext() else { return }

        let node = RenamedKeyPortNode(context: context)
        node.input.value = 7
        let savedID = node.input.id

        // Rewrite the snapshot to a pre-rename key. Hydration matches exactly:
        // the state must not land on today's port, and the retired key must
        // surface as dropped rather than disappear.
        let decoded = try roundTrip(node, context: context) { jsonObject in
            var ports = jsonObject["ports"] as? [[String: Any]] ?? []
            for index in ports.indices where ports[index]["name"] as? String == "input"
            {
                ports[index]["name"] = "legacyInput"
            }
            jsonObject["ports"] = ports
        }

        #expect(decoded.input.id != savedID)
        #expect(decoded.droppedPortStateKeys == ["legacyInput"])
    }
}

/// Stands in for the remove-then-recreate a material sync performs when a
/// uniform's backing type changes underneath an already hydrated port.
private final class RecreatingPortNode: Node
{
    override class var name: String { "Recreating Port" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Test node that rebuilds a declared port during decode." }

    var value: NodePort<Float> { port(named: "value") }

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [
            ("value", NodePort<Float>(name: "Value", kind: .Inlet)),
        ]
    }

    required init(context: Context)
    {
        super.init(context: context)
    }

    required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        self.removePort(self.value)
        self.addDynamicPort(NodePort<Float>(name: "Value", kind: .Inlet), name: "value")
    }
}

private final class RenamedKeyPortNode: Node
{
    override class var name: String { "Renamed Key Port" }
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
}
