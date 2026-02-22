import Foundation

struct MCPVector2: Codable {
    let x: Double
    let y: Double
}

struct MCPBoolResult: Codable {
    let success: Bool
    let error: String?
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
