import Foundation

struct MCPVector2: Codable {
    let x: Double
    let y: Double
}

struct MCPBoolResult: Codable {
    let success: Bool
    let error: String?
    let errorDetails: MCPErrorDetails?
}

struct MCPErrorDetails: Codable {
    let code: String
    let message: String
    let expectedFormat: String?
    let receivedType: String?
    let portType: String?
    let example: String?
}

struct MCPGraphIDResponse: Codable {
    let graphID: String
}

struct MCPNodeClassInfoResponse: Codable {
    let nodeName: String
    let nodeClassName: String
    let nodeType: String
    let nodeDescription: String
}

struct MCPPortInfoResponse: Codable {
    let portID: String
    let name: String
    let description: String
    let kind: String
    let dataType: String
    let connections: [String]
}

struct MCPNodeInfoResponse: Codable {
    let nodeID: String
    let nodeName: String
    let nodeDescription: String
    let nodeType: String
    let nodeOffset: MCPVector2
    let nodeSize: MCPVector2
    let inputPorts: [MCPPortInfoResponse]
    let outputPorts: [MCPPortInfoResponse]
}

enum MCPJSONValue: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([MCPJSONValue])
    case object([String: MCPJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([MCPJSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: MCPJSONValue].self) {
            self = .object(value)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

struct MCPParameterPortValueResponse: Codable {
    let graphID: String
    let nodeID: String
    let portID: String
    let portType: String
    let expectedFormat: String
    let exampleValue: MCPJSONValue?
    let value: MCPJSONValue?
}

struct MCPGraphChangesResponse: Codable {
    let graphID: String
    let revisionToken: String
    let changedNodeIDs: [String]
    let addedNodeIDs: [String]
    let removedNodeIDs: [String]
}

struct MCPToolingHintsResponse: Codable {
    let canonicalFlows: [String]
    let parameterWriteRules: [String]
    let compactPayloadDefaults: [String]
    let graphChangeRules: [String]
}
