import Foundation
import simd
import Fabric

struct MCPPortDescriptor: Codable {
    let id: String
    let name: String
    let kind: String
    let portType: String
    let published: Bool
    let connections: [String]
}

struct MCPNodeDescriptor: Codable {
    let id: String
    let nodeClass: String
    let name: String
    let displayName: String?
    let nodeType: String
    let offset: MCPVector2
    let isSelected: Bool
    let ports: [MCPPortDescriptor]
}

struct MCPGraphSnapshot: Codable {
    let graphID: String
    let nodeCount: Int
    let selectedNodeCount: Int
    let nodes: [MCPNodeDescriptor]
}

struct MCPEditorContext: Codable {
    let hasFocusedDocument: Bool
    let activeGraphId: String
    let totalNodes: Int
    let selectedNodeIds: [String]
    let scrollOffset: MCPVector2
}

struct MCPNodeTypeDescriptor: Codable {
    let id: String
    let name: String
    let nodeType: String
    let className: String
    let summary: String
}

struct MCPVector2: Codable {
    let x: Double
    let y: Double
}

struct MCPApplyOperationsRequest: Codable {
    let operations: [MCPApplyOperation]
}

struct MCPApplyOperation: Codable {
    let kind: String

    let nodeTypeName: String?
    let nodeId: String?
    let fromNodeId: String?
    let fromPortName: String?
    let toNodeId: String?
    let toPortName: String?
    let x: Double?
    let y: Double?
    let displayName: String?
    let portName: String?
    let value: MCPValue?
    let nodeIds: [String]?
}

struct MCPApplyOperationResult: Codable {
    let index: Int
    let kind: String
    let success: Bool
    let message: String
    let affectedNodeIDs: [String]
}

struct MCPApplyResponse: Codable {
    let success: Bool
    let operationCount: Int
    let results: [MCPApplyOperationResult]
}

enum MCPValue: Codable {
    case bool(Bool)
    case int(Int)
    case float(Double)
    case string(String)
    case vector2([Double])
    case vector3([Double])
    case vector4([Double])

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum ValueType: String, Codable {
        case bool
        case int
        case float
        case string
        case vector2
        case vector3
        case vector4
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)

        switch type {
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .int:
            self = .int(try container.decode(Int.self, forKey: .value))
        case .float:
            self = .float(try container.decode(Double.self, forKey: .value))
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .vector2:
            self = .vector2(try container.decode([Double].self, forKey: .value))
        case .vector3:
            self = .vector3(try container.decode([Double].self, forKey: .value))
        case .vector4:
            self = .vector4(try container.decode([Double].self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .bool(let value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case .int(let value):
            try container.encode(ValueType.int, forKey: .type)
            try container.encode(value, forKey: .value)
        case .float(let value):
            try container.encode(ValueType.float, forKey: .type)
            try container.encode(value, forKey: .value)
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .vector2(let value):
            try container.encode(ValueType.vector2, forKey: .type)
            try container.encode(value, forKey: .value)
        case .vector3(let value):
            try container.encode(ValueType.vector3, forKey: .type)
            try container.encode(value, forKey: .value)
        case .vector4(let value):
            try container.encode(ValueType.vector4, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}
