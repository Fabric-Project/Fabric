import Foundation
import simd
#if canImport(Fabric)
import Fabric

@MainActor
final class FabricEditorMCPBridge {
    static let shared = FabricEditorMCPBridge()
    
    private struct GraphChangeState {
        var revision: Int
        var nodeFingerprints: [UUID: String]
        var graphFingerprint: String
    }
    
    private var graphChangeStateByGraphID: [UUID: GraphChangeState] = [:]

    private init() {}

    enum BridgeError: Error, LocalizedError {
        case noFocusedDocument
        case graphNodeNotFound(String)
        case portNotFound(nodeID: String, portName: String)
        case incompatiblePorts(from: String, to: String)
        case invalidOperation(String)

        var errorDescription: String? {
            switch self {
            case .noFocusedDocument:
                return "No focused Fabric document"
            case .graphNodeNotFound(let id):
                return "Node not found: \(id)"
            case .portNotFound(let nodeID, let portName):
                return "Port not found: \(nodeID).\(portName)"
            case .incompatiblePorts(let from, let to):
                return "Incompatible ports: \(from) -> \(to)"
            case .invalidOperation(let value):
                return "Invalid operation: \(value)"
            }
        }
    }

    private func activeGraph() throws -> Graph {
        guard let document = EditorDocumentStore.shared.focusedDocument else {
            throw BridgeError.noFocusedDocument
        }

        return document.graph.activeSubGraph ?? document.graph
    }

    func getActiveDocumentGraphID() throws -> MCPGraphIDResponse {
        let graph = try self.activeGraph()
        return MCPGraphIDResponse(graphID: graph.id.uuidString)
    }

    func makeNewDocument() -> MCPGraphIDResponse {
        let document = EditorDocumentStore.shared.createNewDocument()
        return MCPGraphIDResponse(graphID: document.graph.id.uuidString)
    }

    func getAvailableNodeTypes() -> [String] {
        let names = NodeRegistry.shared.availableNodes.map { $0.nodeType.description }
        return Array(Set(names)).sorted()
    }

    func getAllAvailableNodeClassNames() -> [String] {
        NodeRegistry.shared.availableNodes.map { String(describing: $0.nodeClass) }.sorted()
    }

    func getNodeClassNames(forNodeType nodeType: String) -> [String] {
        NodeRegistry.shared.availableNodes
            .filter { $0.nodeType.description == nodeType }
            .map { String(describing: $0.nodeClass) }
            .sorted()
    }

    func getNodeClassInfo(nodeName: String) -> MCPNodeClassInfoResponse? {
        guard let nodeWrapper = self.nodeClassWrapper(nodeNameOrClassName: nodeName) else {
            return nil
        }

        return MCPNodeClassInfoResponse(
            nodeName: nodeWrapper.nodeName,
            nodeClassName: String(describing: nodeWrapper.nodeClass),
            nodeType: nodeWrapper.nodeType.description,
            nodeDescription: ""
        )
    }

    func getInstantiatedGraphNodes(
        graphID: UUID,
        includePorts: Bool = false,
        includeDescriptions: Bool = false
    ) throws -> [MCPNodeInfoResponse] {
        let graph = try self.graph(for: graphID)
        return graph.nodes.map { self.nodeInfo(for: $0, includePorts: includePorts, includeDescriptions: includeDescriptions) }
    }

    func instantiateNodeClass(graphID: UUID, nodeClassName: String) -> MCPBoolResult {
        do {
            let graph = try self.graph(for: graphID)
            guard let nodeWrapper = self.nodeClassWrapper(nodeNameOrClassName: nodeClassName) else {
                return MCPBoolResult(success: false, error: "Unknown node class: \(nodeClassName)", errorDetails: nil)
            }

            try graph.addNode(nodeWrapper)
            return MCPBoolResult(success: true, error: nil, errorDetails: nil)
        } catch {
            return MCPBoolResult(success: false, error: error.localizedDescription, errorDetails: nil)
        }
    }

    func deleteNode(graphID: UUID, nodeID: UUID) -> MCPBoolResult {
        do {
            let graph = try self.graph(for: graphID)
            let didDelete = graph.deleteNode(forID: nodeID)
            return didDelete
                ? MCPBoolResult(success: true, error: nil, errorDetails: nil)
                : MCPBoolResult(success: false, error: "Node not found: \(nodeID.uuidString)", errorDetails: nil)
        } catch {
            return MCPBoolResult(success: false, error: error.localizedDescription, errorDetails: nil)
        }
    }

    func getNodeInfo(
        graphID: UUID,
        nodeID: UUID,
        includePorts: Bool = false,
        includeDescriptions: Bool = false
    ) throws -> MCPNodeInfoResponse {
        let graph = try self.graph(for: graphID)
        guard let node = graph.node(forID: nodeID) else {
            throw BridgeError.graphNodeNotFound(nodeID.uuidString)
        }

        return self.nodeInfo(for: node, includePorts: includePorts, includeDescriptions: includeDescriptions)
    }

    func moveNodeToOffset(graphID: UUID, nodeID: UUID, offset: MCPVector2) -> MCPBoolResult {
        do {
            let graph = try self.graph(for: graphID)
            guard let node = graph.node(forID: nodeID) else {
                return MCPBoolResult(success: false, error: "Node not found: \(nodeID.uuidString)", errorDetails: nil)
            }

            node.offset = CGSize(width: offset.x, height: offset.y)
            return MCPBoolResult(success: true, error: nil, errorDetails: nil)
        } catch {
            return MCPBoolResult(success: false, error: error.localizedDescription, errorDetails: nil)
        }
    }

    func connectNodePortToNodePort(
        graphID: UUID,
        sourceNodeID: UUID,
        sourcePortID: UUID,
        destinationNodeID: UUID,
        destinationPortID: UUID
    ) -> MCPBoolResult {
        do {
            let graph = try self.graph(for: graphID)
            let sourceNode = try self.node(for: sourceNodeID, in: graph)
            let destinationNode = try self.node(for: destinationNodeID, in: graph)

            let sourcePort = try self.port(for: sourcePortID, in: sourceNode)
            let destinationPort = try self.port(for: destinationPortID, in: destinationNode)

            guard sourcePort.canConnect(to: destinationPort) else {
                return MCPBoolResult(success: false, error: "Incompatible ports", errorDetails: nil)
            }

            sourcePort.connect(to: destinationPort)
            return MCPBoolResult(success: true, error: nil, errorDetails: nil)
        } catch {
            return MCPBoolResult(success: false, error: error.localizedDescription, errorDetails: nil)
        }
    }

    func disconnectNodePortToNodePort(
        graphID: UUID,
        sourceNodeID: UUID,
        sourcePortID: UUID,
        destinationNodeID: UUID,
        destinationPortID: UUID
    ) -> MCPBoolResult {
        do {
            let graph = try self.graph(for: graphID)
            let sourceNode = try self.node(for: sourceNodeID, in: graph)
            let destinationNode = try self.node(for: destinationNodeID, in: graph)

            let sourcePort = try self.port(for: sourcePortID, in: sourceNode)
            let destinationPort = try self.port(for: destinationPortID, in: destinationNode)

            sourcePort.disconnect(from: destinationPort)
            return MCPBoolResult(success: true, error: nil, errorDetails: nil)
        } catch {
            return MCPBoolResult(success: false, error: error.localizedDescription, errorDetails: nil)
        }
    }

    func getToolingHints() -> MCPToolingHintsResponse {
        MCPToolingHintsResponse(
            canonicalFlows: [
                "Read/inspect flow: fabric_get_active_document_graph -> fabric_get_instantiated_graph_nodes(includePorts=false) -> fabric_get_node_info(includePorts=true) for target nodes only.",
                "Edit flow: inspect -> mutate (instantiate/move/connect/write) -> verify with fabric_get_graph_changes.",
                "Parameter flow: always call fabric_read_parameter_port_value before fabric_write_parameter_port_value."
            ],
            parameterWriteRules: [
                "Use raw JSON values only; never stringified JSON.",
                "Optional envelope is supported: {\"portType\":\"...\",\"value\":...}.",
                "Use expectedFormat + exampleValue from read response to shape writes."
            ],
            compactPayloadDefaults: [
                "fabric_get_instantiated_graph_nodes defaults to includePorts=false, includeDescriptions=false.",
                "fabric_get_node_info defaults to includePorts=false, includeDescriptions=false."
            ],
            graphChangeRules: [
                "Use fabric_get_graph_changes with previous revisionToken to avoid repeated full snapshots.",
                "If token matches current revision, changedNodeIDs/addedNodeIDs/removedNodeIDs are empty."
            ]
        )
    }

    func readParameterPortValue(graphID: UUID, nodeID: UUID, portID: UUID) throws -> MCPParameterPortValueResponse {
        let graph = try self.graph(for: graphID)
        let node = try self.node(for: nodeID, in: graph)
        let port = try self.port(for: portID, in: node)

        guard port.parameter != nil else {
            throw BridgeError.invalidOperation("Port is not a parameter port: \(portID.uuidString)")
        }

        return MCPParameterPortValueResponse(
            graphID: graphID.uuidString,
            nodeID: nodeID.uuidString,
            portID: portID.uuidString,
            portType: port.portType.rawValue,
            expectedFormat: self.expectedParameterFormat(for: port.portType),
            exampleValue: self.exampleParameterValue(for: port.portType),
            value: self.parameterPortValue(for: port)
        )
    }

    func writeParameterPortValue(graphID: UUID, nodeID: UUID, portID: UUID, portValue: Any) -> MCPBoolResult {
        do {
            let graph = try self.graph(for: graphID)
            let node = try self.node(for: nodeID, in: graph)
            let port = try self.port(for: portID, in: node)

            guard port.parameter != nil else {
                return MCPBoolResult(success: false, error: "Port is not a parameter port: \(portID.uuidString)", errorDetails: nil)
            }
            
            let (value, maybePortTypeFromEnvelope) = self.unwrapParameterWriteEnvelope(portValue)
            if let maybePortTypeFromEnvelope, maybePortTypeFromEnvelope != port.portType.rawValue {
                return MCPBoolResult(
                    success: false,
                    error: "portType mismatch in envelope",
                    errorDetails: MCPErrorDetails(
                        code: "parameter_port_type_mismatch",
                        message: "Envelope portType does not match target port type.",
                        expectedFormat: self.expectedParameterFormat(for: port.portType),
                        receivedType: maybePortTypeFromEnvelope,
                        portType: port.portType.rawValue,
                        example: self.exampleParameterValue(for: port.portType).flatMap { self.jsonString(from: $0) }
                    )
                )
            }

            do {
                try self.setParameterPortValue(port: port, rawValue: value)
                return MCPBoolResult(success: true, error: nil, errorDetails: nil)
            } catch {
                let details = self.parameterErrorDetails(for: error, port: port, receivedValue: value)
                return MCPBoolResult(success: false, error: error.localizedDescription, errorDetails: details)
            }
        } catch {
            let details = MCPErrorDetails(
                code: "parameter_write_invalid_target",
                message: error.localizedDescription,
                expectedFormat: nil,
                receivedType: nil,
                portType: nil,
                example: nil
            )
            return MCPBoolResult(success: false, error: error.localizedDescription, errorDetails: details)
        }
    }

    func getGraphChanges(graphID: UUID, sinceRevisionToken: String?) throws -> MCPGraphChangesResponse {
        let graph = try self.graph(for: graphID)
        let nodeFingerprints = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, self.nodeFingerprint(for: $0)) })
        let graphFingerprint = self.graphFingerprint(from: nodeFingerprints)

        let currentState = self.graphChangeStateByGraphID[graphID]
        if let currentState, currentState.graphFingerprint == graphFingerprint {
            return MCPGraphChangesResponse(
                graphID: graphID.uuidString,
                revisionToken: self.revisionToken(for: currentState.revision),
                changedNodeIDs: [],
                addedNodeIDs: [],
                removedNodeIDs: []
            )
        }

        let previousFingerprints = currentState?.nodeFingerprints ?? [:]
        let added = Set(nodeFingerprints.keys).subtracting(previousFingerprints.keys)
        let removed = Set(previousFingerprints.keys).subtracting(nodeFingerprints.keys)
        let common = Set(nodeFingerprints.keys).intersection(previousFingerprints.keys)
        let changed = common.filter { previousFingerprints[$0] != nodeFingerprints[$0] }

        let nextRevision = max(self.revisionValue(from: sinceRevisionToken) ?? 0, currentState?.revision ?? 0) + 1
        let nextState = GraphChangeState(revision: nextRevision, nodeFingerprints: nodeFingerprints, graphFingerprint: graphFingerprint)
        self.graphChangeStateByGraphID[graphID] = nextState

        return MCPGraphChangesResponse(
            graphID: graphID.uuidString,
            revisionToken: self.revisionToken(for: nextRevision),
            changedNodeIDs: changed.map(\.uuidString).sorted(),
            addedNodeIDs: added.map(\.uuidString).sorted(),
            removedNodeIDs: removed.map(\.uuidString).sorted()
        )
    }

    private func graph(for graphID: UUID) throws -> Graph {
        guard let graph = EditorDocumentStore.shared.graph(for: graphID) else {
            throw BridgeError.invalidOperation("Graph not found: \(graphID.uuidString)")
        }
        return graph
    }

    private func node(for id: UUID, in graph: Graph) throws -> Node {
        guard let node = graph.node(forID: id) else {
            throw BridgeError.graphNodeNotFound(id.uuidString)
        }
        return node
    }

    private func port(for portID: UUID, in node: Node) throws -> Fabric.Port {
        guard let port = node.ports.first(where: { $0.id == portID }) else {
            throw BridgeError.portNotFound(nodeID: node.id.uuidString, portName: portID.uuidString)
        }
        return port
    }

    private func nodeClassWrapper(nodeNameOrClassName: String) -> NodeClassWrapper? {
        NodeRegistry.shared.availableNodes.first {
            $0.nodeName == nodeNameOrClassName || String(describing: $0.nodeClass) == nodeNameOrClassName
        }
    }

    private func nodeInfo(for node: Node, includePorts: Bool, includeDescriptions: Bool) -> MCPNodeInfoResponse {
        let inputPorts = includePorts
            ? node.ports.filter { $0.kind == .Inlet }.map { self.portInfo(for: $0, includeDescriptions: includeDescriptions) }
            : []
        let outputPorts = includePorts
            ? node.ports.filter { $0.kind == .Outlet }.map { self.portInfo(for: $0, includeDescriptions: includeDescriptions) }
            : []

        return MCPNodeInfoResponse(
            nodeID: node.id.uuidString,
            nodeName: node.name,
            nodeDescription: includeDescriptions ? "" : "",
            nodeType: node.nodeType.description,
            nodeOffset: MCPVector2(x: node.offset.width, y: node.offset.height),
            nodeSize: MCPVector2(x: node.nodeSize.width, y: node.nodeSize.height),
            inputPorts: inputPorts,
            outputPorts: outputPorts
        )
    }

    private func portInfo(for port: Fabric.Port, includeDescriptions: Bool) -> MCPPortInfoResponse {
        MCPPortInfoResponse(
            portID: port.id.uuidString,
            name: port.name,
            description: includeDescriptions ? port.portDescription : "",
            kind: port.kind.rawValue,
            dataType: port.portType.rawValue,
            connections: port.connections.map { $0.id.uuidString }
        )
    }

    private func parameterPortValue(for port: Fabric.Port) -> MCPJSONValue? {
        if let typedPort = port as? ParameterPort<Bool> {
            return typedPort.value.map(MCPJSONValue.bool)
        }
        if let typedPort = port as? ParameterPort<Int> {
            return typedPort.value.map(MCPJSONValue.int)
        }
        if let typedPort = port as? ParameterPort<Float> {
            return typedPort.value.map { MCPJSONValue.double(Double($0)) }
        }
        if let typedPort = port as? ParameterPort<String> {
            return typedPort.value.map(MCPJSONValue.string)
        }
        if let typedPort = port as? ParameterPort<simd_float2>, let value = typedPort.value {
            return .array([.double(Double(value.x)), .double(Double(value.y))])
        }
        if let typedPort = port as? ParameterPort<simd_float3>, let value = typedPort.value {
            return .array([.double(Double(value.x)), .double(Double(value.y)), .double(Double(value.z))])
        }
        if let typedPort = port as? ParameterPort<simd_float4>, let value = typedPort.value {
            return .array([.double(Double(value.x)), .double(Double(value.y)), .double(Double(value.z)), .double(Double(value.w))])
        }
        if let typedPort = port as? ParameterPort<simd_quatf>, let value = typedPort.value {
            return .array([.double(Double(value.vector.x)), .double(Double(value.vector.y)), .double(Double(value.vector.z)), .double(Double(value.vector.w))])
        }
        if let typedPort = port as? ParameterPort<simd_float4x4>, let value = typedPort.value {
            let flattened = [
                value.columns.0.x, value.columns.0.y, value.columns.0.z, value.columns.0.w,
                value.columns.1.x, value.columns.1.y, value.columns.1.z, value.columns.1.w,
                value.columns.2.x, value.columns.2.y, value.columns.2.z, value.columns.2.w,
                value.columns.3.x, value.columns.3.y, value.columns.3.z, value.columns.3.w,
            ]
            return .array(flattened.map { MCPJSONValue.double(Double($0)) })
        }

        if let typedPort = port as? ParameterPort<ContiguousArray<Bool>>, let value = typedPort.value {
            return .array(value.map(MCPJSONValue.bool))
        }
        if let typedPort = port as? ParameterPort<ContiguousArray<Int>>, let value = typedPort.value {
            return .array(value.map(MCPJSONValue.int))
        }
        if let typedPort = port as? ParameterPort<ContiguousArray<Float>>, let value = typedPort.value {
            return .array(value.map { MCPJSONValue.double(Double($0)) })
        }
        if let typedPort = port as? ParameterPort<ContiguousArray<String>>, let value = typedPort.value {
            return .array(value.map(MCPJSONValue.string))
        }

        return nil
    }

    private func setParameterPortValue(port: Fabric.Port, rawValue: Any) throws {
        if let typedPort = port as? ParameterPort<Bool> {
            guard let value = self.boolValue(from: rawValue) else {
                throw BridgeError.invalidOperation("Expected Bool for \(port.portType.rawValue). Format: \(self.expectedParameterFormat(for: port.portType))")
            }
            typedPort.value = value
            return
        }
        if let typedPort = port as? ParameterPort<Int> {
            guard let value = self.intValue(from: rawValue) else {
                throw BridgeError.invalidOperation("Expected Int for \(port.portType.rawValue). Format: \(self.expectedParameterFormat(for: port.portType))")
            }
            typedPort.value = value
            return
        }
        if let typedPort = port as? ParameterPort<Float> {
            guard let value = self.doubleValue(from: rawValue) else {
                throw BridgeError.invalidOperation("Expected Number for \(port.portType.rawValue). Format: \(self.expectedParameterFormat(for: port.portType))")
            }
            typedPort.value = Float(value)
            return
        }
        if let typedPort = port as? ParameterPort<String> {
            guard let value = rawValue as? String else {
                throw BridgeError.invalidOperation("Expected String for \(port.portType.rawValue). Format: \(self.expectedParameterFormat(for: port.portType))")
            }
            typedPort.value = value
            return
        }
        if let typedPort = port as? ParameterPort<simd_float2> {
            let values = try self.floatArray(from: rawValue, count: 2)
            typedPort.value = simd_float2(values[0], values[1])
            return
        }
        if let typedPort = port as? ParameterPort<simd_float3> {
            let values = try self.floatArray(from: rawValue, count: 3)
            typedPort.value = simd_float3(values[0], values[1], values[2])
            return
        }
        if let typedPort = port as? ParameterPort<simd_float4> {
            let values = try self.floatArray(from: rawValue, count: 4)
            typedPort.value = simd_float4(values[0], values[1], values[2], values[3])
            return
        }
        if let typedPort = port as? ParameterPort<simd_quatf> {
            let values = try self.floatArray(from: rawValue, count: 4)
            typedPort.value = simd_quatf(vector: simd_float4(values[0], values[1], values[2], values[3]))
            return
        }
        if let typedPort = port as? ParameterPort<simd_float4x4> {
            let values = try self.floatArray(from: rawValue, count: 16)
            typedPort.value = simd_float4x4(columns: (
                simd_float4(values[0], values[1], values[2], values[3]),
                simd_float4(values[4], values[5], values[6], values[7]),
                simd_float4(values[8], values[9], values[10], values[11]),
                simd_float4(values[12], values[13], values[14], values[15])
            ))
            return
        }

        if let typedPort = port as? ParameterPort<ContiguousArray<Bool>> {
            guard let values = rawValue as? [Any] else {
                throw BridgeError.invalidOperation("Expected [Bool] for \(port.portType.rawValue). Format: \(self.expectedParameterFormat(for: port.portType))")
            }
            let parsed = values.compactMap(self.boolValue(from:))
            guard parsed.count == values.count else {
                throw BridgeError.invalidOperation("Expected [Bool] for \(port.portType.rawValue). Format: \(self.expectedParameterFormat(for: port.portType))")
            }
            typedPort.value = ContiguousArray(parsed)
            return
        }
        if let typedPort = port as? ParameterPort<ContiguousArray<Int>> {
            guard let values = rawValue as? [Any] else {
                throw BridgeError.invalidOperation("Expected [Int] for \(port.portType.rawValue). Format: \(self.expectedParameterFormat(for: port.portType))")
            }
            let parsed = values.compactMap(self.intValue(from:))
            guard parsed.count == values.count else {
                throw BridgeError.invalidOperation("Expected [Int] for \(port.portType.rawValue). Format: \(self.expectedParameterFormat(for: port.portType))")
            }
            typedPort.value = ContiguousArray(parsed)
            return
        }
        if let typedPort = port as? ParameterPort<ContiguousArray<Float>> {
            guard let values = rawValue as? [Any] else {
                throw BridgeError.invalidOperation("Expected [Number] for \(port.portType.rawValue). Format: \(self.expectedParameterFormat(for: port.portType))")
            }
            let parsed = values.compactMap(self.doubleValue(from:)).map(Float.init)
            guard parsed.count == values.count else {
                throw BridgeError.invalidOperation("Expected [Number] for \(port.portType.rawValue). Format: \(self.expectedParameterFormat(for: port.portType))")
            }
            typedPort.value = ContiguousArray(parsed)
            return
        }
        if let typedPort = port as? ParameterPort<ContiguousArray<String>> {
            guard let values = rawValue as? [String] else {
                throw BridgeError.invalidOperation("Expected [String] for \(port.portType.rawValue). Format: \(self.expectedParameterFormat(for: port.portType))")
            }
            typedPort.value = ContiguousArray(values)
            return
        }

        throw BridgeError.invalidOperation("Unsupported parameter port type: \(port.portType.rawValue)")
    }

    private func unwrapParameterWriteEnvelope(_ rawValue: Any) -> (Any, String?) {
        guard let envelope = rawValue as? [String: Any], let value = envelope["value"] else {
            return (rawValue, nil)
        }
        return (value, envelope["portType"] as? String)
    }

    private func boolValue(from rawValue: Any) -> Bool? {
        if let value = rawValue as? Bool { return value }
        if let value = rawValue as? NSNumber { return value.boolValue }
        return nil
    }

    private func intValue(from rawValue: Any) -> Int? {
        if let value = rawValue as? Int { return value }
        if let value = rawValue as? NSNumber { return value.intValue }
        return nil
    }

    private func doubleValue(from rawValue: Any) -> Double? {
        if let value = rawValue as? Double { return value }
        if let value = rawValue as? Int { return Double(value) }
        if let value = rawValue as? NSNumber { return value.doubleValue }
        return nil
    }

    private func floatArray(from rawValue: Any, count: Int) throws -> [Float] {
        guard let values = rawValue as? [Any], values.count == count else {
            throw BridgeError.invalidOperation("Expected array with \(count) numeric values")
        }

        let parsed = values.compactMap(self.doubleValue(from:)).map(Float.init)
        guard parsed.count == count else {
            throw BridgeError.invalidOperation("Expected array with \(count) numeric values")
        }

        return parsed
    }

    private func expectedParameterFormat(for portType: PortType) -> String {
        switch portType {
        case .Bool:
            return "boolean (example: true)"
        case .Int:
            return "integer number (example: 3)"
        case .Float:
            return "number (example: 1.25)"
        case .String:
            return "string (example: \"hello\")"
        case .Vector2:
            return "array of 2 numbers (example: [0.1, 0.2])"
        case .Vector3:
            return "array of 3 numbers (example: [0.1, 0.2, 0.3])"
        case .Vector4, .Color:
            return "array of 4 numbers (example: [0.1, 0.2, 0.3, 1.0])"
        case .Quaternion:
            return "array of 4 numbers (x,y,z,w)"
        case .Transform:
            return "array of 16 numbers (column-major 4x4 matrix)"
        case .Array(let elementType):
            return "array of \(elementType.rawValue) values"
        case .Geometry, .Material, .Shader, .Image, .Virtual:
            return "unsupported for parameter write via MCP"
        }
    }
    
    private func exampleParameterValue(for portType: PortType) -> MCPJSONValue? {
        switch portType {
        case .Bool:
            return .bool(true)
        case .Int:
            return .int(3)
        case .Float:
            return .double(1.25)
        case .String:
            return .string("hello")
        case .Vector2:
            return .array([.double(0.1), .double(0.2)])
        case .Vector3:
            return .array([.double(0.1), .double(0.2), .double(0.3)])
        case .Vector4, .Color, .Quaternion:
            return .array([.double(0.1), .double(0.2), .double(0.3), .double(1.0)])
        case .Transform:
            return .array(Array(repeating: MCPJSONValue.double(0.0), count: 16))
        case .Array(let elementType):
            switch elementType {
            case .Bool: return .array([.bool(true), .bool(false)])
            case .Int: return .array([.int(1), .int(2)])
            case .Float: return .array([.double(1.0), .double(2.0)])
            case .String: return .array([.string("a"), .string("b")])
            default: return nil
            }
        case .Geometry, .Material, .Shader, .Image, .Virtual:
            return nil
        }
    }
    
    private func parameterErrorDetails(for error: Error, port: Fabric.Port, receivedValue: Any) -> MCPErrorDetails {
        let message: String
        if case .invalidOperation(let value) = error as? BridgeError {
            message = value
        } else {
            message = error.localizedDescription
        }
        return MCPErrorDetails(
            code: "parameter_write_invalid_value",
            message: message,
            expectedFormat: self.expectedParameterFormat(for: port.portType),
            receivedType: String(describing: type(of: receivedValue)),
            portType: port.portType.rawValue,
            example: self.exampleParameterValue(for: port.portType).flatMap { self.jsonString(from: $0) }
        )
    }
    
    private func nodeFingerprint(for node: Node) -> String {
        let portSig = node.ports.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id.uuidString)|\($0.kind.rawValue)|\($0.portType.rawValue)|\($0.connections.map(\.id.uuidString).sorted().joined(separator: ","))"
        }.joined(separator: ";")
        return "\(node.id.uuidString)|\(node.name)|\(node.offset.width),\(node.offset.height)|\(node.nodeSize.width),\(node.nodeSize.height)|\(portSig)"
    }

    private func graphFingerprint(from map: [UUID: String]) -> String {
        map.keys.sorted { $0.uuidString < $1.uuidString }
            .compactMap { map[$0] }
            .joined(separator: "||")
    }
    
    private func revisionToken(for revision: Int) -> String {
        "r\(revision)"
    }
    
    private func revisionValue(from token: String?) -> Int? {
        guard let token else { return nil }
        let value = token.hasPrefix("r") ? String(token.dropFirst()) : token
        return Int(value)
    }
    
    private func jsonString(from value: MCPJSONValue) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
#endif
