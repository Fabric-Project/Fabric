import Foundation

private func serviceLog(_ message: String) {
    let line = "[FabricMCPService] \(message)"
    NSLog("%@", line)
    appendServiceTraceLog(line)
}

private func appendServiceTraceLog(_ line: String) {
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

private actor FabricEditorExecutionClient {
    private let serviceName: String
    private var connection: NSXPCConnection?

    init(serviceName: String) {
        self.serviceName = serviceName
        serviceLog("initialized editor client for serviceName=\(serviceName)")
    }

    func callTool(tool: FabricMCPTool, argumentsJSON: String) async throws -> String {
        serviceLog("forward start tool=\(tool.name) rawValue=\(tool.rawValue) argsBytes=\(argumentsJSON.utf8.count)")
        let connection = try await self.connectIfNeeded()

        return try await withCheckedThrowingContinuation { continuation in
            guard let remote = connection.remoteObjectProxyWithErrorHandler({ error in
                serviceLog("forward XPC error tool=\(tool.name) error=\(error.localizedDescription)")
                continuation.resume(throwing: FabricMPCServiceError.editorExecutionFailed(error.localizedDescription))
            }) as? FabricMCPEditorExecutionProtocol else {
                continuation.resume(throwing: FabricMPCServiceError.unableToCreateEditorProxy)
                return
            }

            remote.callTool(toolRawValue: tool.rawValue, argumentsJSON: argumentsJSON) { response, error in
                if let response {
                    serviceLog("forward success tool=\(tool.name) responseBytes=\(response.utf8.count)")
                    continuation.resume(returning: response)
                    return
                }

                serviceLog("forward failure tool=\(tool.name) error=\(error ?? "Unknown XPC error")")
                continuation.resume(throwing: FabricMPCServiceError.editorExecutionFailed(error ?? "Unknown XPC error"))
            }
        }
    }

    private func connectIfNeeded() async throws -> NSXPCConnection {
        if let existing = self.connection {
            serviceLog("reusing editor execution connection serviceName=\(self.serviceName)")
            return existing
        }

        let serviceName = self.serviceName
        serviceLog("opening editor execution XPC connection serviceName=\(serviceName)")
        let connection = NSXPCConnection(machServiceName: self.serviceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: FabricMCPEditorExecutionProtocol.self)
        connection.invalidationHandler = {
            serviceLog("editor execution XPC invalidated serviceName=\(serviceName)")
        }
        connection.interruptionHandler = {
            serviceLog("editor execution XPC interrupted serviceName=\(serviceName)")
        }
        connection.resume()

        self.connection = connection

        let isAlive = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            guard let remote = connection.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: FabricMPCServiceError.editorExecutionFailed(error.localizedDescription))
            }) as? FabricMCPEditorExecutionProtocol else {
                continuation.resume(throwing: FabricMPCServiceError.unableToCreateEditorProxy)
                return
            }

            remote.ping { isAlive in
                continuation.resume(returning: isAlive)
            }
        }

        guard isAlive else {
            throw FabricMPCServiceError.editorExecutionUnavailable(self.serviceName)
        }

        serviceLog("editor execution XPC ping succeeded serviceName=\(self.serviceName)")
        return connection
    }
}

private enum FabricMPCServiceError: LocalizedError {
    case unknownTool(Int)
    case unableToCreateEditorProxy
    case editorExecutionUnavailable(String)
    case editorExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let rawValue):
            return "Unknown tool raw value: \(rawValue)"
        case .unableToCreateEditorProxy:
            return "Failed to create editor execution proxy"
        case .editorExecutionUnavailable(let serviceName):
            return "Editor execution unavailable: \(serviceName)"
        case .editorExecutionFailed(let message):
            return message
        }
    }
}

final class FabricMPCService: NSObject, FabricMCPServiceProtocol {
    private let editorClient: FabricEditorExecutionClient

    override init() {
        let serviceName = ProcessInfo.processInfo.environment["FABRIC_EDITOR_EXECUTION_SERVICE_NAME"] ?? FabricMCPServiceNames.editorExecution
        self.editorClient = FabricEditorExecutionClient(serviceName: serviceName)
        super.init()
        serviceLog("service initialized executionService=\(serviceName)")
    }

    func ping(_ reply: @escaping (Bool) -> Void) {
        serviceLog("ping received")
        reply(true)
    }

    func callTool(toolRawValue: Int, argumentsJSON: String, reply: @escaping (String?, String?) -> Void) {
        serviceLog("callTool received rawValue=\(toolRawValue) argsBytes=\(argumentsJSON.utf8.count)")
        guard let tool = FabricMCPTool(rawValue: toolRawValue) else {
            serviceLog("callTool unknown rawValue=\(toolRawValue)")
            reply(nil, FabricMPCServiceError.unknownTool(toolRawValue).localizedDescription)
            return
        }

        Task {
            do {
                let result = try await self.editorClient.callTool(tool: tool, argumentsJSON: argumentsJSON)
                serviceLog("callTool returning success tool=\(tool.name)")
                reply(result, nil)
            } catch {
                serviceLog("callTool returning failure tool=\(tool.name) error=\(error.localizedDescription)")
                reply(nil, error.localizedDescription)
            }
        }
    }
}
