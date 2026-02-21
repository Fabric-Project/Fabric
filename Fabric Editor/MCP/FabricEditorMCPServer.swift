import Foundation
import MCP

actor FabricEditorMCPServer {
    static let shared = FabricEditorMCPServer()

    private var serverTask: Task<Void, Never>?

    private init() {}

    func startIfEnabled()
    {
        
//        guard self.serverTask == nil else { return }
//
//        let shouldStart = CommandLine.arguments.contains("--mcp-stdio") || ProcessInfo.processInfo.environment["FABRIC_MCP_STDIO"] == "1"
//        guard shouldStart else { return }

        self.serverTask = Task {
            await self.runServer()
        }
    }

    private func runServer() async {
        let server = Server(
            name: "fabric-editor",
            version: "0.1.0",
            capabilities: Server.Capabilities(
                tools: .init(listChanged: false)
            )
        )

        await server.withMethodHandler(ListTools.self) { _ in
            let tools = [
                Tool(
                    name: "fabric_get_editor_context",
                    description: "Return the currently focused Fabric document and graph context.",
                    inputSchema: .object([:])
                ),
                Tool(
                    name: "fabric_list_node_types",
                    description: "List available Fabric node types from the editor registry.",
                    inputSchema: .object([:])
                ),
                Tool(
                    name: "fabric_get_graph_snapshot",
                    description: "Return nodes, ports, and connections for the active graph.",
                    inputSchema: .object([:])
                ),
                Tool(
                    name: "fabric_get_node_details",
                    description: "Return full details for a single node by UUID.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "nodeId": .object([
                                "type": .string("string")
                            ])
                        ]),
                        "required": .array([.string("nodeId")])
                    ])
                ),
                Tool(
                    name: "fabric_validate_operations",
                    description: "Validate graph edit operations JSON without mutating the document.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "operationsJson": .object([
                                "type": .string("string")
                            ])
                        ]),
                        "required": .array([.string("operationsJson")])
                    ])
                ),
                Tool(
                    name: "fabric_apply_operations",
                    description: "Apply graph edit operations JSON to the focused document.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "operationsJson": .object([
                                "type": .string("string")
                            ])
                        ]),
                        "required": .array([.string("operationsJson")])
                    ])
                ),
            ]

            return ListTools.Result(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                let response = try await self.callTool(params)
                return CallTool.Result(content: [.text(response)], isError: false)
            } catch {
                return CallTool.Result(content: [.text("{\"error\":\"\(error.localizedDescription)\"}")], isError: true)
            }
        }

        do {
            let transport = StdioTransport()
            try await server.start(transport: transport)

            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(3600))
            }
        } catch {
            fputs("Fabric MCP server failed: \(error)\n", stderr)
        }
    }

    private func callTool(_ params: CallTool.Parameters) async throws -> String {
        let bridge = await MainActor.run { FabricEditorMCPBridge.shared }

        switch params.name {
        case "fabric_get_editor_context":
            let context = try await MainActor.run { try bridge.getEditorContext() }
            return try self.serializeJSON(context)

        case "fabric_list_node_types":
            let nodeTypes = await MainActor.run { bridge.listNodeTypes() }
            return try self.serializeJSON(nodeTypes)

        case "fabric_get_graph_snapshot":
            let selectedOnly = params.arguments?["selectedOnly"]?.boolValue ?? false
            let nodeIdStrings = params.arguments?["nodeIds"]?.arrayValue?.compactMap { $0.stringValue } ?? []
            let nodeIds = Set(nodeIdStrings.compactMap(UUID.init(uuidString:)))

            let snapshot = try await MainActor.run {
                try bridge.getGraphSnapshot(selectedOnly: selectedOnly, nodeIDs: nodeIds)
            }
            return try self.serializeJSON(snapshot)

        case "fabric_get_node_details":
            guard let nodeIdString = params.arguments?["nodeId"]?.stringValue,
                  let nodeId = UUID(uuidString: nodeIdString) else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("nodeId is required")
            }

            let details = try await MainActor.run {
                try bridge.getNodeDetails(nodeID: nodeId)
            }
            return try self.serializeJSON(details)

        case "fabric_validate_operations", "fabric_apply_operations":
            guard let operationsJson = params.arguments?["operationsJson"]?.stringValue else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("operationsJson is required")
            }

            let requestData = Data(operationsJson.utf8)
            let request = try JSONDecoder().decode(MCPApplyOperationsRequest.self, from: requestData)

            let result = try await MainActor.run {
                if params.name == "fabric_validate_operations" {
                    return try bridge.validateOperations(request)
                }
                return try bridge.applyOperations(request)
            }

            return try self.serializeJSON(result)

        default:
            throw FabricEditorMCPBridge.BridgeError.invalidOperation("Unknown tool: \(params.name)")
        }
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
