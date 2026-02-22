import Foundation

public enum FabricMCPTool: Int, CaseIterable, Sendable {
    case getEditorContext = 1
    case listNodeTypes = 2
    case getGraphSnapshot = 3
    case getNodeDetails = 4
    case validateOperations = 5
    case applyOperations = 6

    public var name: String {
        switch self {
        case .getEditorContext:
            return "fabric_get_editor_context"
        case .listNodeTypes:
            return "fabric_list_node_types"
        case .getGraphSnapshot:
            return "fabric_get_graph_snapshot"
        case .getNodeDetails:
            return "fabric_get_node_details"
        case .validateOperations:
            return "fabric_validate_operations"
        case .applyOperations:
            return "fabric_apply_operations"
        }
    }

    public var summary: String {
        switch self {
        case .getEditorContext:
            return "Return the currently focused Fabric document and graph context."
        case .listNodeTypes:
            return "List available Fabric node types from the editor registry."
        case .getGraphSnapshot:
            return "Return nodes, ports, and connections for the active graph."
        case .getNodeDetails:
            return "Return full details for a single node by UUID."
        case .validateOperations:
            return "Validate graph edit operations JSON without mutating the document."
        case .applyOperations:
            return "Apply graph edit operations JSON to the focused document."
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
