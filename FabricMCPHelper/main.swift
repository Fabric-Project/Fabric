import Foundation
import MCP

private func helperLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[FabricMCPHelper] \(timestamp) \(message)"
    fputs("\(line)\n", stderr)
    appendTraceLog(line)
}

private func appendTraceLog(_ line: String) {
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

private actor FabricMCPServiceClient {
    private let serviceName: String
    private var connection: NSXPCConnection?

    init(serviceName: String) {
        self.serviceName = serviceName
        helperLog("initialized service client for serviceName=\(serviceName)")
    }

    func callTool(tool: FabricMCPTool, arguments: [String: Value]?) async throws -> String {
        helperLog("tool call start name=\(tool.name) rawValue=\(tool.rawValue)")
        let argumentsJSON = try self.serializeArguments(arguments)
        helperLog("tool call encoded args bytes=\(argumentsJSON.utf8.count)")
        let connection = try await self.connectIfNeeded()

        return try await withCheckedThrowingContinuation { continuation in
            guard let remote = connection.remoteObjectProxyWithErrorHandler({ error in
                helperLog("tool call XPC error name=\(tool.name) error=\(error.localizedDescription)")
                continuation.resume(throwing: XPCBridgeError.remoteFailure(error.localizedDescription))
            }) as? FabricMCPServiceProtocol else {
                continuation.resume(throwing: XPCBridgeError.unableToCreateProxy)
                return
            }

            remote.callTool(toolRawValue: tool.rawValue, argumentsJSON: argumentsJSON) { response, error in
                if let response {
                    helperLog("tool call success name=\(tool.name) responseBytes=\(response.utf8.count)")
                    continuation.resume(returning: response)
                    return
                }

                let message = error ?? "Unknown XPC error"
                helperLog("tool call failure name=\(tool.name) error=\(message)")
                continuation.resume(throwing: XPCBridgeError.remoteFailure(message))
            }
        }
    }

    private func connectIfNeeded() async throws -> NSXPCConnection {
        if let existing = self.connection {
            helperLog("reusing existing XPC connection to serviceName=\(self.serviceName)")
            return existing
        }

        let serviceName = self.serviceName
        helperLog("opening XPC connection serviceName=\(serviceName)")
        let connection = NSXPCConnection(serviceName: self.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: FabricMCPServiceProtocol.self)

        connection.invalidationHandler = { [weak connection] in
            helperLog("XPC connection invalidated serviceName=\(serviceName)")
            connection?.invalidationHandler = nil
        }

        connection.interruptionHandler = { [weak connection] in
            helperLog("XPC connection interrupted serviceName=\(serviceName)")
            connection?.interruptionHandler = nil
        }

        connection.resume()
        self.connection = connection

        let isAlive = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            guard let remote = connection.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: XPCBridgeError.remoteFailure(error.localizedDescription))
            }) as? FabricMCPServiceProtocol else {
                continuation.resume(throwing: XPCBridgeError.unableToCreateProxy)
                return
            }

            remote.ping { isAlive in
                continuation.resume(returning: isAlive)
            }
        }

        guard isAlive else {
            throw XPCBridgeError.serviceUnavailable(self.serviceName)
        }

        helperLog("XPC ping succeeded serviceName=\(self.serviceName)")
        return connection
    }

    private func serializeArguments(_ arguments: [String: Value]?) throws -> String {
        let object = arguments ?? [:]
        let foundationObject = try object.mapValues { try self.foundationValue(from: $0) }
        let data = try JSONSerialization.data(withJSONObject: foundationObject, options: [])

        guard let string = String(data: data, encoding: .utf8) else {
            throw XPCBridgeError.argumentsEncodingFailed
        }

        return string
    }

    private func foundationValue(from value: Value) throws -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let bool):
            return bool
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .string(let string):
            return string
        case .data(_, let data):
            return data.base64EncodedString()
        case .array(let array):
            return try array.map { try self.foundationValue(from: $0) }
        case .object(let object):
            return try object.mapValues { try self.foundationValue(from: $0) }
        }
    }
}

private enum XPCBridgeError: LocalizedError {
    case unableToCreateProxy
    case serviceUnavailable(String)
    case remoteFailure(String)
    case argumentsEncodingFailed

    var errorDescription: String? {
        switch self {
        case .unableToCreateProxy:
            return "Failed to create XPC proxy"
        case .serviceUnavailable(let serviceName):
            return "XPC service unavailable: \(serviceName)"
        case .remoteFailure(let message):
            return message
        case .argumentsEncodingFailed:
            return "Failed to encode tool arguments"
        }
    }
}

private let toolDefinitions: [Tool] = FabricMCPTool.allCases.map { tool in
    Tool(name: tool.name, description: tool.summary, inputSchema: tool.inputSchema)
}

private let serviceName =
    ProcessInfo.processInfo.environment["FABRIC_MCP_SERVICE_NAME"] ??
    FabricMCPServiceNames.mcpService
private let xpcClient = FabricMCPServiceClient(serviceName: serviceName)

private let server = Server(
    name: "fabric-editor",
    version: "0.1.0",
    capabilities: Server.Capabilities(tools: .init(listChanged: false))
)

Task {
    helperLog("starting MCP server serviceName=\(serviceName)")
    await server.withMethodHandler(ListTools.self) { _ in
        helperLog("ListTools request received")
        return ListTools.Result(tools: toolDefinitions)
    }

    await server.withMethodHandler(CallTool.self) { params in
        helperLog("CallTool request received name=\(params.name)")
        do {
            guard let tool = FabricMCPTool.from(mcpToolName: params.name) else {
                helperLog("CallTool unknown tool name=\(params.name)")
                return CallTool.Result(content: [.text("Unknown tool name: \(params.name)")], isError: true)
            }

            let response = try await xpcClient.callTool(tool: tool, arguments: params.arguments)
            return CallTool.Result(content: [.text(response)], isError: false)
        } catch {
            helperLog("CallTool failed name=\(params.name) error=\(error.localizedDescription)")
            return CallTool.Result(content: [.text("\(error.localizedDescription)")], isError: true)
        }
    }

    do {
        let transport = StdioTransport()
        helperLog("starting stdio transport")
        try await server.start(transport: transport)
        helperLog("stdio transport started")

        while !Task.isCancelled {
            try await Task.sleep(for: .seconds(3600))
        }
    } catch {
        fputs("FabricMCPHelper failed: \(error)\n", stderr)
        exit(1)
    }
}

RunLoop.main.run()

private extension FabricMCPTool {
    var inputSchema: Value {
        switch self {
        case .getActiveDocumentGraph, .makeNewDocument, .getAvailableNodeTypes, .getAllAvailableNodeClassNames:
            return .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        case .getNodeClassNamesForNodeType:
            return .object([
                "type": .string("object"),
                "properties": .object([
                    "nodeType": .object([
                        "type": .string("string")
                    ])
                ]),
                "required": .array([.string("nodeType")])
            ])
        case .getNodeClassInfo:
            return .object([
                "type": .string("object"),
                "properties": .object([
                    "nodeName": .object([
                        "type": .string("string")
                    ])
                ]),
                "required": .array([.string("nodeName")])
            ])
        case .getInstantiatedGraphNodes:
            return .object([
                "type": .string("object"),
                "properties": .object([
                    "graphID": .object([
                        "type": .string("string")
                    ])
                ]),
                "required": .array([.string("graphID")])
            ])
        case .instantiateNodeClass:
            return .object([
                "type": .string("object"),
                "properties": .object([
                    "graphID": .object(["type": .string("string")]),
                    "nodeClass": .object(["type": .string("string")])
                ]),
                "required": .array([.string("graphID"), .string("nodeClass")])
            ])
        case .deleteNode, .getNodeInfo:
            return .object([
                "type": .string("object"),
                "properties": .object([
                    "graphID": .object(["type": .string("string")]),
                    "nodeID": .object(["type": .string("string")])
                ]),
                "required": .array([.string("graphID"), .string("nodeID")])
            ])
        case .moveNodeToOffset:
            return .object([
                "type": .string("object"),
                "properties": .object([
                    "graphID": .object(["type": .string("string")]),
                    "nodeID": .object(["type": .string("string")]),
                    "offset": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "x": .object(["type": .string("number")]),
                            "y": .object(["type": .string("number")])
                        ]),
                        "required": .array([.string("x"), .string("y")])
                    ])
                ]),
                "required": .array([.string("graphID"), .string("nodeID"), .string("offset")])
            ])
        case .connectNodePortToNodePort, .disconnectNodePortToNodePort:
            return .object([
                "type": .string("object"),
                "properties": .object([
                    "graphID": .object(["type": .string("string")]),
                    "sourceNode": .object(["type": .string("string")]),
                    "sourcePort": .object(["type": .string("string")]),
                    "destNode": .object(["type": .string("string")]),
                    "destinationPort": .object(["type": .string("string")])
                ]),
                "required": .array([
                    .string("graphID"),
                    .string("sourceNode"),
                    .string("sourcePort"),
                    .string("destNode"),
                    .string("destinationPort")
                ])
            ])
        }
    }
}
