import Foundation

private func editorToolLog(_ message: String) {
    let line = "[FabricEditorToolExecutor] \(message)"
    NSLog("%@", line)
    appendEditorToolTraceLog(line)
}

private func appendEditorToolTraceLog(_ line: String) {
    let logURL = URL(filePath: "/tmp/fabric-mcp-trace.log")
    let payload = Data((line + "\n").utf8)
    if let handle = try? FileHandle(forWritingTo: logURL) {
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } catch {
            // Ignore trace write failures.
        }
        return
    }

    try? payload.write(to: logURL, options: .atomic)
}

@MainActor
final class FabricEditorMCPToolExecutor {
    static let shared = FabricEditorMCPToolExecutor()

    private init() {}

    func callTool(toolRawValue: Int, argumentsJSON: String) throws -> String {
        editorToolLog("callTool entry rawValue=\(toolRawValue) argsBytes=\(argumentsJSON.utf8.count)")
        guard let tool = FabricMCPTool(rawValue: toolRawValue) else {
            editorToolLog("callTool unknown rawValue=\(toolRawValue)")
            throw FabricEditorMCPBridge.BridgeError.invalidOperation("Unknown tool raw value: \(toolRawValue)")
        }

        return try self.callTool(tool: tool, argumentsJSON: argumentsJSON)
    }

    func callTool(tool: FabricMCPTool, argumentsJSON: String) throws -> String {
        editorToolLog("executing tool=\(tool.name) argsBytes=\(argumentsJSON.utf8.count)")
        let arguments = try self.decodeArguments(from: argumentsJSON)
        let bridge = FabricEditorMCPBridge.shared

        switch tool {
        case .getEditorContext:
            let context = try bridge.getEditorContext()
            editorToolLog("tool success tool=\(tool.name)")
            return try self.serializeJSON(context)

        case .listNodeTypes:
            let nodeTypes = bridge.listNodeTypes()
            editorToolLog("tool success tool=\(tool.name) count=\(nodeTypes.count)")
            return try self.serializeJSON(nodeTypes)

        case .getGraphSnapshot:
            let selectedOnly = arguments.boolValue(for: "selectedOnly") ?? false
            let nodeIdStrings = arguments.stringArrayValue(for: "nodeIds") ?? []
            let nodeIDs = Set(nodeIdStrings.compactMap(UUID.init(uuidString:)))
            let snapshot = try bridge.getGraphSnapshot(selectedOnly: selectedOnly, nodeIDs: nodeIDs)
            editorToolLog("tool success tool=\(tool.name) nodeCount=\(snapshot.nodeCount)")
            return try self.serializeJSON(snapshot)

        case .getNodeDetails:
            guard
                let nodeIDString = arguments.stringValue(for: "nodeId"),
                let nodeID = UUID(uuidString: nodeIDString)
            else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("nodeId is required")
            }

            let details = try bridge.getNodeDetails(nodeID: nodeID)
            editorToolLog("tool success tool=\(tool.name) nodeId=\(nodeID.uuidString)")
            return try self.serializeJSON(details)

        case .validateOperations, .applyOperations:
            guard let operationsJSONString = arguments.stringValue(for: "operationsJson") else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("operationsJson is required")
            }

            let requestData = Data(operationsJSONString.utf8)
            let request = try JSONDecoder().decode(MCPApplyOperationsRequest.self, from: requestData)
            let response: MCPApplyResponse

            if tool == .validateOperations {
                response = try bridge.validateOperations(request)
            } else {
                response = try bridge.applyOperations(request)
            }

            editorToolLog("tool success tool=\(tool.name) operationCount=\(response.operationCount) success=\(response.success)")
            return try self.serializeJSON(response)
        }
    }

    private func decodeArguments(from argumentsJSON: String) throws -> [String: Any] {
        guard let data = argumentsJSON.data(using: .utf8) else {
            throw FabricEditorMCPBridge.BridgeError.invalidOperation("argumentsJSON is not valid UTF-8")
        }

        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let object = decoded as? [String: Any] else {
            throw FabricEditorMCPBridge.BridgeError.invalidOperation("argumentsJSON must be a JSON object")
        }

        return object
    }

    private func serializeJSON(_ payload: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(AnyEncodable(payload))
        guard let string = String(data: data, encoding: .utf8) else {
            throw FabricEditorMCPBridge.BridgeError.invalidOperation("Failed to encode JSON response")
        }

        return string
    }
}

private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        self.encodeFunc = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try self.encodeFunc(encoder)
    }
}

private extension Dictionary where Key == String, Value == Any {
    func stringValue(for key: String) -> String? {
        self[key] as? String
    }

    func boolValue(for key: String) -> Bool? {
        self[key] as? Bool
    }

    func stringArrayValue(for key: String) -> [String]? {
        guard let raw = self[key] as? [Any] else { return nil }
        return raw.compactMap { $0 as? String }
    }
}
