import Foundation
import simd
import Fabric

@MainActor
final class FabricEditorMCPBridge {
    static let shared = FabricEditorMCPBridge()

    private init() {}

    enum BridgeError: Error, LocalizedError {
        case noFocusedDocument
        case graphNodeNotFound(String)
        case portNotFound(nodeID: String, portName: String)
        case incompatiblePorts(from: String, to: String)
        case invalidUUID(String)
        case unknownNodeType(String)
        case invalidOperation(String)
        case invalidParameterValue(String)

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
            case .invalidUUID(let value):
                return "Invalid UUID: \(value)"
            case .unknownNodeType(let value):
                return "Unknown node type: \(value)"
            case .invalidOperation(let value):
                return "Invalid operation: \(value)"
            case .invalidParameterValue(let value):
                return "Invalid parameter value: \(value)"
            }
        }
    }

    private func activeGraph() throws -> Graph {
        guard let document = EditorDocumentStore.shared.focusedDocument else {
            throw BridgeError.noFocusedDocument
        }

        return document.graph.activeSubGraph ?? document.graph
    }

    func getEditorContext() throws -> MCPEditorContext {
        let graph = try self.activeGraph()
        let selectedNodeIDs = graph.nodes.filter { $0.isSelected }.map { $0.id.uuidString }

        return MCPEditorContext(
            hasFocusedDocument: true,
            activeGraphId: graph.id.uuidString,
            totalNodes: graph.nodes.count,
            selectedNodeIds: selectedNodeIDs,
            scrollOffset: MCPVector2(x: graph.currentScrollOffset.x, y: graph.currentScrollOffset.y)
        )
    }

    func listNodeTypes() -> [MCPNodeTypeDescriptor] {
        NodeRegistry.shared.availableNodes.map { node in
            MCPNodeTypeDescriptor(
                id: node.id.uuidString,
                name: node.nodeName,
                nodeType: node.nodeType.description,
                className: String(describing: node.nodeClass),
                summary: node.nodeClass.nodeDescription
            )
        }
    }

    func getGraphSnapshot(selectedOnly: Bool = false, nodeIDs: Set<UUID> = []) throws -> MCPGraphSnapshot {
        let graph = try self.activeGraph()

        var nodes = graph.nodes
        if selectedOnly {
            nodes = nodes.filter { $0.isSelected }
        }
        if !nodeIDs.isEmpty {
            nodes = nodes.filter { nodeIDs.contains($0.id) }
        }

        let descriptors = nodes.map(self.nodeDescriptor(for:))

        return MCPGraphSnapshot(
            graphID: graph.id.uuidString,
            nodeCount: graph.nodes.count,
            selectedNodeCount: graph.nodes.filter { $0.isSelected }.count,
            nodes: descriptors
        )
    }

    func getNodeDetails(nodeID: UUID) throws -> MCPNodeDescriptor {
        let graph = try self.activeGraph()
        guard let node = graph.node(forID: nodeID) else {
            throw BridgeError.graphNodeNotFound(nodeID.uuidString)
        }

        return self.nodeDescriptor(for: node)
    }

    func validateOperations(_ request: MCPApplyOperationsRequest) throws -> MCPApplyResponse {
        let graph = try self.activeGraph()

        var results: [MCPApplyOperationResult] = []
        for (index, operation) in request.operations.enumerated() {
            do {
                try self.validate(operation: operation, graph: graph)
                results.append(MCPApplyOperationResult(index: index, kind: operation.kind, success: true, message: "ok", affectedNodeIDs: []))
            } catch {
                results.append(MCPApplyOperationResult(index: index, kind: operation.kind, success: false, message: error.localizedDescription, affectedNodeIDs: []))
            }
        }

        return MCPApplyResponse(success: results.allSatisfy(\.success), operationCount: request.operations.count, results: results)
    }

    func applyOperations(_ request: MCPApplyOperationsRequest) throws -> MCPApplyResponse {
        let graph = try self.activeGraph()

        for operation in request.operations {
            try self.validate(operation: operation, graph: graph)
        }

        graph.undoManager?.beginUndoGrouping()
        defer {
            graph.undoManager?.endUndoGrouping()
            graph.undoManager?.setActionName("MCP Apply Operations")
        }

        var results: [MCPApplyOperationResult] = []

        for (index, operation) in request.operations.enumerated() {
            do {
                let affected = try self.execute(operation: operation, graph: graph)
                results.append(MCPApplyOperationResult(index: index, kind: operation.kind, success: true, message: "ok", affectedNodeIDs: affected))
            } catch {
                results.append(MCPApplyOperationResult(index: index, kind: operation.kind, success: false, message: error.localizedDescription, affectedNodeIDs: []))
                throw error
            }
        }

        return MCPApplyResponse(success: true, operationCount: request.operations.count, results: results)
    }

    private func validate(operation: MCPApplyOperation, graph: Graph) throws {
        switch operation.kind {
        case "addNode":
            guard let nodeTypeName = operation.nodeTypeName, !nodeTypeName.isEmpty else {
                throw BridgeError.invalidOperation("addNode requires nodeTypeName")
            }
            guard NodeRegistry.shared.availableNodes.contains(where: { $0.nodeName == nodeTypeName || String(describing: $0.nodeClass) == nodeTypeName }) else {
                throw BridgeError.unknownNodeType(nodeTypeName)
            }

        case "deleteNode", "moveNode", "renameNode":
            guard let nodeId = operation.nodeId else {
                throw BridgeError.invalidOperation("\(operation.kind) requires nodeId")
            }
            _ = try self.node(for: nodeId, graph: graph)

        case "connectPorts", "disconnectPorts":
            let fromNodeId = operation.fromNodeId ?? ""
            let fromPortName = operation.fromPortName ?? ""
            let toNodeId = operation.toNodeId ?? ""
            let toPortName = operation.toPortName ?? ""

            let fromPort = try self.port(nodeID: fromNodeId, portName: fromPortName, graph: graph)
            let toPort = try self.port(nodeID: toNodeId, portName: toPortName, graph: graph)

            if operation.kind == "connectPorts" {
                guard fromPort.canConnect(to: toPort) else {
                    throw BridgeError.incompatiblePorts(from: "\(fromNodeId).\(fromPortName)", to: "\(toNodeId).\(toPortName)")
                }
            }

        case "setParameterValue":
            let nodeId = operation.nodeId ?? ""
            let portName = operation.portName ?? ""
            _ = try self.port(nodeID: nodeId, portName: portName, graph: graph)
            guard operation.value != nil else {
                throw BridgeError.invalidOperation("setParameterValue requires value")
            }

        case "selectNodes":
            guard operation.nodeIds != nil else {
                throw BridgeError.invalidOperation("selectNodes requires nodeIds")
            }

        default:
            throw BridgeError.invalidOperation("Unknown kind: \(operation.kind)")
        }
    }

    private func execute(operation: MCPApplyOperation, graph: Graph) throws -> [String] {
        switch operation.kind {
        case "addNode":
            guard let nodeTypeName = operation.nodeTypeName else {
                throw BridgeError.invalidOperation("addNode requires nodeTypeName")
            }

            guard let nodeWrapper = NodeRegistry.shared.availableNodes.first(where: { $0.nodeName == nodeTypeName || String(describing: $0.nodeClass) == nodeTypeName }) else {
                throw BridgeError.unknownNodeType(nodeTypeName)
            }

            try graph.addNode(nodeWrapper)

            guard let newNode = graph.nodes.last else {
                throw BridgeError.invalidOperation("Failed to add node")
            }

            if let x = operation.x, let y = operation.y {
                newNode.offset = CGSize(width: x, height: y)
            }

            return [newNode.id.uuidString]

        case "deleteNode":
            guard let nodeId = operation.nodeId, let uuid = UUID(uuidString: nodeId) else {
                throw BridgeError.invalidOperation("deleteNode requires valid nodeId")
            }

            let didDelete = graph.deleteNode(forID: uuid)
            if !didDelete { throw BridgeError.graphNodeNotFound(nodeId) }
            return [nodeId]

        case "moveNode":
            guard let nodeId = operation.nodeId else {
                throw BridgeError.invalidOperation("moveNode requires nodeId")
            }

            let node = try self.node(for: nodeId, graph: graph)
            guard let x = operation.x, let y = operation.y else {
                throw BridgeError.invalidOperation("moveNode requires x and y")
            }

            node.offset = CGSize(width: x, height: y)
            return [node.id.uuidString]

        case "renameNode":
            guard let nodeId = operation.nodeId else {
                throw BridgeError.invalidOperation("renameNode requires nodeId")
            }
            let node = try self.node(for: nodeId, graph: graph)
            node.displayName = operation.displayName
            return [node.id.uuidString]

        case "connectPorts":
            let fromNodeId = operation.fromNodeId ?? ""
            let fromPortName = operation.fromPortName ?? ""
            let toNodeId = operation.toNodeId ?? ""
            let toPortName = operation.toPortName ?? ""

            let fromPort = try self.port(nodeID: fromNodeId, portName: fromPortName, graph: graph)
            let toPort = try self.port(nodeID: toNodeId, portName: toPortName, graph: graph)

            guard fromPort.canConnect(to: toPort) else {
                throw BridgeError.incompatiblePorts(from: "\(fromNodeId).\(fromPortName)", to: "\(toNodeId).\(toPortName)")
            }

            fromPort.connect(to: toPort)
            return [fromNodeId, toNodeId]

        case "disconnectPorts":
            let fromNodeId = operation.fromNodeId ?? ""
            let fromPortName = operation.fromPortName ?? ""
            let toNodeId = operation.toNodeId ?? ""
            let toPortName = operation.toPortName ?? ""

            let fromPort = try self.port(nodeID: fromNodeId, portName: fromPortName, graph: graph)
            let toPort = try self.port(nodeID: toNodeId, portName: toPortName, graph: graph)
            fromPort.disconnect(from: toPort)
            return [fromNodeId, toNodeId]

        case "setParameterValue":
            let nodeId = operation.nodeId ?? ""
            let portName = operation.portName ?? ""
            let port = try self.port(nodeID: nodeId, portName: portName, graph: graph)
            guard let value = operation.value else {
                throw BridgeError.invalidOperation("setParameterValue requires value")
            }

            try self.setPortValue(port: port, value: value)
            return [nodeId]

        case "selectNodes":
            let nodeIds = operation.nodeIds ?? []
            graph.deselectAllNodes()

            for nodeID in nodeIds {
                let node = try self.node(for: nodeID, graph: graph)
                node.isSelected = true
            }

            return nodeIds

        default:
            throw BridgeError.invalidOperation("Unknown kind: \(operation.kind)")
        }
    }

    private func node(for id: String, graph: Graph) throws -> Node {
        guard let uuid = UUID(uuidString: id) else {
            throw BridgeError.invalidUUID(id)
        }

        guard let node = graph.node(forID: uuid) else {
            throw BridgeError.graphNodeNotFound(id)
        }

        return node
    }

    private func port(nodeID: String, portName: String, graph: Graph) throws -> Fabric.Port {
        let node = try self.node(for: nodeID, graph: graph)

        guard let port = node.ports.first(where: { $0.name == portName }) else {
            throw BridgeError.portNotFound(nodeID: nodeID, portName: portName)
        }

        return port
    }

    private func setPortValue(port: Fabric.Port, value: MCPValue) throws {
        switch (port, value) {
        case (let typedPort as NodePort<Bool>, .bool(let boolValue)):
            typedPort.value = boolValue

        case (let typedPort as NodePort<Int>, .int(let intValue)):
            typedPort.value = intValue

        case (let typedPort as NodePort<Float>, .float(let floatValue)):
            typedPort.value = Float(floatValue)

        case (let typedPort as NodePort<String>, .string(let stringValue)):
            typedPort.value = stringValue

        case (let typedPort as NodePort<simd_float2>, .vector2(let values)):
            guard values.count == 2 else { throw BridgeError.invalidParameterValue("Expected 2 values for vector2") }
            typedPort.value = simd_float2(Float(values[0]), Float(values[1]))

        case (let typedPort as NodePort<simd_float3>, .vector3(let values)):
            guard values.count == 3 else { throw BridgeError.invalidParameterValue("Expected 3 values for vector3") }
            typedPort.value = simd_float3(Float(values[0]), Float(values[1]), Float(values[2]))

        case (let typedPort as NodePort<simd_float4>, .vector4(let values)):
            guard values.count == 4 else { throw BridgeError.invalidParameterValue("Expected 4 values for vector4") }
            typedPort.value = simd_float4(Float(values[0]), Float(values[1]), Float(values[2]), Float(values[3]))

        default:
            throw BridgeError.invalidParameterValue("Unsupported value for port \(port.name): \(port.portType.rawValue)")
        }
    }

    private func nodeDescriptor(for node: Node) -> MCPNodeDescriptor {
        let ports = node.ports.map { port in
            MCPPortDescriptor(
                id: port.id.uuidString,
                name: port.name,
                kind: port.kind.rawValue,
                portType: port.portType.rawValue,
                published: port.published,
                connections: port.connections.map { $0.id.uuidString }
            )
        }

        return MCPNodeDescriptor(
            id: node.id.uuidString,
            nodeClass: String(describing: type(of: node)),
            name: node.name,
            displayName: node.displayName,
            nodeType: node.nodeType.description,
            offset: MCPVector2(x: node.offset.width, y: node.offset.height),
            isSelected: node.isSelected,
            ports: ports
        )
    }
}
