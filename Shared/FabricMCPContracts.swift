import Foundation

public enum FabricMCPTool: Int, CaseIterable, Sendable {
    case getActiveDocumentGraph = 1
    case makeNewDocument = 2
    case getAvailableNodeTypes = 3
    case getAllAvailableNodeClassNames = 4
    case getNodeClassNamesForNodeType = 5
    case getNodeClassInfo = 6
    case getInstantiatedGraphNodes = 7
    case instantiateNodeClass = 8
    case deleteNode = 9
    case getNodeInfo = 10
    case moveNodeToOffset = 11
    case connectNodePortToNodePort = 12
    case disconnectNodePortToNodePort = 13
    case readParameterPortValue = 14
    case writeParameterPortValue = 15
    case getToolingHints = 16
    case getGraphChanges = 17

    public var name: String {
        switch self {
        case .getActiveDocumentGraph:
            return "fabric_get_active_document_graph"
        case .makeNewDocument:
            return "fabric_make_new_document"
        case .getAvailableNodeTypes:
            return "fabric_get_available_node_types"
        case .getAllAvailableNodeClassNames:
            return "fabric_get_all_available_node_class_names"
        case .getNodeClassNamesForNodeType:
            return "fabric_get_node_class_names_for_node_type"
        case .getNodeClassInfo:
            return "fabric_get_node_class_info"
        case .getInstantiatedGraphNodes:
            return "fabric_get_instantiated_graph_nodes"
        case .instantiateNodeClass:
            return "fabric_instantiate_node_class"
        case .deleteNode:
            return "fabric_delete_node"
        case .getNodeInfo:
            return "fabric_get_node_info"
        case .moveNodeToOffset:
            return "fabric_move_node_to_offset"
        case .connectNodePortToNodePort:
            return "fabric_connect_node_port_to_node_port"
        case .disconnectNodePortToNodePort:
            return "fabric_disconnect_node_port_to_node_port"
        case .readParameterPortValue:
            return "fabric_read_parameter_port_value"
        case .writeParameterPortValue:
            return "fabric_write_parameter_port_value"
        case .getToolingHints:
            return "fabric_get_tooling_hints"
        case .getGraphChanges:
            return "fabric_get_graph_changes"
        }
    }

    public var summary: String {
        switch self {
        case .getActiveDocumentGraph:
            return "Get the active document's graph UUID."
        case .makeNewDocument:
            return "Create a new document and return its graph UUID."
        case .getAvailableNodeTypes:
            return "Get available node type names."
        case .getAllAvailableNodeClassNames:
            return "Get all available node class names."
        case .getNodeClassNamesForNodeType:
            return "Get available node class names for a specific node type."
        case .getNodeClassInfo:
            return "Get metadata for a node class or node name."
        case .getInstantiatedGraphNodes:
            return "List instantiated nodes in a graph with ports metadata."
        case .instantiateNodeClass:
            return "Instantiate a node class in a graph."
        case .deleteNode:
            return "Delete a node instance from a graph."
        case .getNodeInfo:
            return "Get detailed metadata for one node instance."
        case .moveNodeToOffset:
            return "Move a node to an offset in graph space."
        case .connectNodePortToNodePort:
            return "Connect source node output port to destination node input port."
        case .disconnectNodePortToNodePort:
            return "Disconnect source node output port from destination node input port."
        case .readParameterPortValue:
            return "Read a parameter port value by graph/node/port UUID."
        case .writeParameterPortValue:
            return "Write a parameter port value by graph/node/port UUID. Use raw JSON values (number/bool/string/array/object), not stringified JSON. Use fabric_read_parameter_port_value first to get portType."
        case .getToolingHints:
            return "Get canonical Fabric MCP workflows, supported formats, and usage hints for efficient tool calling."
        case .getGraphChanges:
            return "Get incremental graph changes since the last observed revision token."
        }
    }

    public static func from(mcpToolName: String) -> FabricMCPTool? {
        Self.allCases.first { $0.name == mcpToolName }
    }
}

public enum FabricMCPServiceNames {
    public static let mcpService = "graphics.fabric.FabricMCPService"
    public static let editorExecution = "graphics.fabric.FabricEditor.MCPExecution"
}

@objc public protocol FabricMCPServiceProtocol {
    func ping(_ reply: @escaping (Bool) -> Void)
    func callTool(toolRawValue: Int, argumentsJSON: String, reply: @escaping (String?, String?) -> Void)
}

@objc public protocol FabricMCPEditorExecutionProtocol {
    func ping(_ reply: @escaping (Bool) -> Void)
    func callTool(toolRawValue: Int, argumentsJSON: String, reply: @escaping (String?, String?) -> Void)
}
