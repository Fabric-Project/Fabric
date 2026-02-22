import Foundation
#if canImport(Fabric)
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

    func getInstantiatedGraphNodes(graphID: UUID) throws -> [MCPNodeInfoResponse] {
        let graph = try self.graph(for: graphID)
        return graph.nodes.map { self.nodeInfo(for: $0) }
    }

    func instantiateNodeClass(graphID: UUID, nodeClassName: String) -> MCPBoolResult {
        do {
            let graph = try self.graph(for: graphID)
            guard let nodeWrapper = self.nodeClassWrapper(nodeNameOrClassName: nodeClassName) else {
                return MCPBoolResult(success: false, error: "Unknown node class: \(nodeClassName)")
            }

            try graph.addNode(nodeWrapper)
            return MCPBoolResult(success: true, error: nil)
        } catch {
            return MCPBoolResult(success: false, error: error.localizedDescription)
        }
    }

    func deleteNode(graphID: UUID, nodeID: UUID) -> MCPBoolResult {
        do {
            let graph = try self.graph(for: graphID)
            let didDelete = graph.deleteNode(forID: nodeID)
            return didDelete
                ? MCPBoolResult(success: true, error: nil)
                : MCPBoolResult(success: false, error: "Node not found: \(nodeID.uuidString)")
        } catch {
            return MCPBoolResult(success: false, error: error.localizedDescription)
        }
    }

    func getNodeInfo(graphID: UUID, nodeID: UUID) throws -> MCPNodeInfoResponse {
        let graph = try self.graph(for: graphID)
        guard let node = graph.node(forID: nodeID) else {
            throw BridgeError.graphNodeNotFound(nodeID.uuidString)
        }

        return self.nodeInfo(for: node)
    }

    func moveNodeToOffset(graphID: UUID, nodeID: UUID, offset: MCPVector2) -> MCPBoolResult {
        do {
            let graph = try self.graph(for: graphID)
            guard let node = graph.node(forID: nodeID) else {
                return MCPBoolResult(success: false, error: "Node not found: \(nodeID.uuidString)")
            }

            node.offset = CGSize(width: offset.x, height: offset.y)
            return MCPBoolResult(success: true, error: nil)
        } catch {
            return MCPBoolResult(success: false, error: error.localizedDescription)
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
                return MCPBoolResult(success: false, error: "Incompatible ports")
            }

            sourcePort.connect(to: destinationPort)
            return MCPBoolResult(success: true, error: nil)
        } catch {
            return MCPBoolResult(success: false, error: error.localizedDescription)
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
            return MCPBoolResult(success: true, error: nil)
        } catch {
            return MCPBoolResult(success: false, error: error.localizedDescription)
        }
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

    private func nodeInfo(for node: Node) -> MCPNodeInfoResponse {
        let inputPorts = node.ports
            .filter { $0.kind == .Inlet }
            .map { self.portInfo(for: $0) }
        let outputPorts = node.ports
            .filter { $0.kind == .Outlet }
            .map { self.portInfo(for: $0) }

        return MCPNodeInfoResponse(
            nodeID: node.id.uuidString,
            nodeName: node.name,
            nodeDescription: "",
            nodeType: node.nodeType.description,
            nodeOffset: MCPVector2(x: node.offset.width, y: node.offset.height),
            nodeSize: MCPVector2(x: node.nodeSize.width, y: node.nodeSize.height),
            inputPorts: inputPorts,
            outputPorts: outputPorts
        )
    }

    private func portInfo(for port: Fabric.Port) -> MCPPortInfoResponse {
        MCPPortInfoResponse(
            portID: port.id.uuidString,
            name: port.name,
            description: port.portDescription,
            kind: port.kind.rawValue,
            dataType: port.portType.rawValue,
            connections: port.connections.map { $0.id.uuidString }
        )
    }
}
#endif
