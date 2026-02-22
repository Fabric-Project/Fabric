import Foundation

private func editorExecutionLog(_ message: String) {
    let line = "[FabricEditorExecution] \(message)"
    NSLog("%@", line)
    appendEditorTraceLog(line)
}

private func appendEditorTraceLog(_ line: String) {
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

final class FabricEditorMCPExecutionServer: NSObject {
    static let shared = FabricEditorMCPExecutionServer()

    private let machServiceName = FabricMCPServiceNames.editorExecution
    private var listener: NSXPCListener?

    private override init() {
        super.init()
    }

    func start() {
        guard self.listener == nil else { return }

        let listener = NSXPCListener(machServiceName: self.machServiceName)
        listener.delegate = self
        listener.resume()

        self.listener = listener
        editorExecutionLog("execution server listening machServiceName=\(self.machServiceName)")
    }
}

extension FabricEditorMCPExecutionServer: NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        editorExecutionLog("accepting new XPC connection")
        let service = FabricEditorMCPExecutionService()

        newConnection.exportedInterface = NSXPCInterface(with: FabricMCPEditorExecutionProtocol.self)
        newConnection.exportedObject = service
        newConnection.resume()

        return true
    }
}

final class FabricEditorMCPExecutionService: NSObject, FabricMCPEditorExecutionProtocol {
    func ping(_ reply: @escaping (Bool) -> Void) {
        editorExecutionLog("ping received")
        reply(true)
    }

    func callTool(toolRawValue: Int, argumentsJSON: String, reply: @escaping (String?, String?) -> Void) {
        editorExecutionLog("callTool received rawValue=\(toolRawValue) argsBytes=\(argumentsJSON.utf8.count)")
        Task {
            do {
                let output = try await MainActor.run {
                    try FabricEditorMCPToolExecutor.shared.callTool(toolRawValue: toolRawValue, argumentsJSON: argumentsJSON)
                }
                editorExecutionLog("callTool success rawValue=\(toolRawValue) responseBytes=\(output.utf8.count)")
                reply(output, nil)
            } catch {
                editorExecutionLog("callTool failure rawValue=\(toolRawValue) error=\(error.localizedDescription)")
                reply(nil, error.localizedDescription)
            }
        }
    }
}
