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
        case .getActiveDocumentGraph:
            let context = try bridge.getActiveDocumentGraphID()
            editorToolLog("tool success tool=\(tool.name)")
            return try self.serializeJSON(context)

        case .makeNewDocument:
            let response = bridge.makeNewDocument()
            editorToolLog("tool success tool=\(tool.name) graphID=\(response.graphID)")
            return try self.serializeJSON(response)

        case .getAvailableNodeTypes:
            let nodeTypes = bridge.getAvailableNodeTypes()
            editorToolLog("tool success tool=\(tool.name) count=\(nodeTypes.count)")
            return try self.serializeJSON(nodeTypes)

        case .getAllAvailableNodeClassNames:
            let classNames = bridge.getAllAvailableNodeClassNames()
            editorToolLog("tool success tool=\(tool.name) count=\(classNames.count)")
            return try self.serializeJSON(classNames)

        case .getNodeClassNamesForNodeType:
            guard let nodeType = arguments.stringValue(for: "nodeType") else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("nodeType is required")
            }
            let classNames = bridge.getNodeClassNames(forNodeType: nodeType)
            editorToolLog("tool success tool=\(tool.name) count=\(classNames.count)")
            return try self.serializeJSON(classNames)

        case .getNodeClassInfo:
            guard let nodeName = arguments.stringValue(for: "nodeName") else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("nodeName is required")
            }
            let info = bridge.getNodeClassInfo(nodeName: nodeName)
            editorToolLog("tool success tool=\(tool.name)")
            return try self.serializeJSON(info)

        case .getInstantiatedGraphNodes:
            guard
                let graphIDString = arguments.stringValue(for: "graphID"),
                let graphID = UUID(uuidString: graphIDString)
            else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("graphID is required")
            }
            let includePorts = arguments.boolValue(for: "includePorts") ?? false
            let includeDescriptions = arguments.boolValue(for: "includeDescriptions") ?? false
            let nodes = try bridge.getInstantiatedGraphNodes(
                graphID: graphID,
                includePorts: includePorts,
                includeDescriptions: includeDescriptions
            )
            editorToolLog("tool success tool=\(tool.name) count=\(nodes.count)")
            return try self.serializeJSON(nodes)

        case .instantiateNodeClass:
            guard
                let graphIDString = arguments.stringValue(for: "graphID"),
                let graphID = UUID(uuidString: graphIDString),
                let nodeClass = arguments.stringValue(for: "nodeClass")
            else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("graphID and nodeClass are required")
            }
            let response = bridge.instantiateNodeClass(graphID: graphID, nodeClassName: nodeClass)
            editorToolLog("tool success tool=\(tool.name) success=\(response.success)")
            return try self.serializeJSON(response)

        case .deleteNode:
            guard
                let graphIDString = arguments.stringValue(for: "graphID"),
                let graphID = UUID(uuidString: graphIDString),
                let nodeIDString = arguments.stringValue(for: "nodeID"),
                let nodeID = UUID(uuidString: nodeIDString)
            else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("graphID and nodeID are required")
            }
            let response = bridge.deleteNode(graphID: graphID, nodeID: nodeID)
            editorToolLog("tool success tool=\(tool.name) success=\(response.success)")
            return try self.serializeJSON(response)

        case .getNodeInfo:
            guard
                let graphIDString = arguments.stringValue(for: "graphID"),
                let graphID = UUID(uuidString: graphIDString),
                let nodeIDString = arguments.stringValue(for: "nodeID"),
                let nodeID = UUID(uuidString: nodeIDString)
            else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("graphID and nodeID are required")
            }
            let includePorts = arguments.boolValue(for: "includePorts") ?? false
            let includeDescriptions = arguments.boolValue(for: "includeDescriptions") ?? false
            let response = try bridge.getNodeInfo(
                graphID: graphID,
                nodeID: nodeID,
                includePorts: includePorts,
                includeDescriptions: includeDescriptions
            )
            editorToolLog("tool success tool=\(tool.name) nodeID=\(nodeID.uuidString)")
            return try self.serializeJSON(response)

        case .moveNodeToOffset:
            guard
                let graphIDString = arguments.stringValue(for: "graphID"),
                let graphID = UUID(uuidString: graphIDString),
                let nodeIDString = arguments.stringValue(for: "nodeID"),
                let nodeID = UUID(uuidString: nodeIDString),
                let offset = arguments.vector2Value(for: "offset")
            else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("graphID, nodeID and offset are required")
            }
            let response = bridge.moveNodeToOffset(graphID: graphID, nodeID: nodeID, offset: offset)
            editorToolLog("tool success tool=\(tool.name) success=\(response.success)")
            return try self.serializeJSON(response)

        case .connectNodePortToNodePort:
            let response = try self.connectOrDisconnect(arguments: arguments, bridge: bridge, connect: true)
            editorToolLog("tool success tool=\(tool.name) success=\(response.success)")
            return try self.serializeJSON(response)

        case .disconnectNodePortToNodePort:
            let response = try self.connectOrDisconnect(arguments: arguments, bridge: bridge, connect: false)
            editorToolLog("tool success tool=\(tool.name) success=\(response.success)")
            return try self.serializeJSON(response)

        case .readParameterPortValue:
            guard
                let graphIDString = arguments.stringValue(for: "graphID"),
                let graphID = UUID(uuidString: graphIDString),
                let nodeIDString = arguments.stringValue(for: "nodeID"),
                let nodeID = UUID(uuidString: nodeIDString),
                let portIDString = arguments.stringValue(for: "portID"),
                let portID = UUID(uuidString: portIDString)
            else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("graphID, nodeID and portID are required")
            }
            let response = try bridge.readParameterPortValue(graphID: graphID, nodeID: nodeID, portID: portID)
            editorToolLog("tool success tool=\(tool.name) portID=\(portID.uuidString)")
            return try self.serializeJSON(response)

        case .writeParameterPortValue:
            guard
                let graphIDString = arguments.stringValue(for: "graphID"),
                let graphID = UUID(uuidString: graphIDString),
                let nodeIDString = arguments.stringValue(for: "nodeID"),
                let nodeID = UUID(uuidString: nodeIDString),
                let portIDString = arguments.stringValue(for: "portID"),
                let portID = UUID(uuidString: portIDString),
                let portValue = arguments["portValue"]
            else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("graphID, nodeID, portID and portValue are required")
            }
            let response = bridge.writeParameterPortValue(
                graphID: graphID,
                nodeID: nodeID,
                portID: portID,
                portValue: portValue
            )
            editorToolLog("tool success tool=\(tool.name) success=\(response.success)")
            return try self.serializeJSON(response)

        case .getToolingHints:
            let response = bridge.getToolingHints()
            editorToolLog("tool success tool=\(tool.name)")
            return try self.serializeJSON(response)

        case .getGraphChanges:
            guard
                let graphIDString = arguments.stringValue(for: "graphID"),
                let graphID = UUID(uuidString: graphIDString)
            else {
                throw FabricEditorMCPBridge.BridgeError.invalidOperation("graphID is required")
            }
            let sinceRevisionToken = arguments.stringValue(for: "sinceRevisionToken")
            let response = try bridge.getGraphChanges(graphID: graphID, sinceRevisionToken: sinceRevisionToken)
            editorToolLog("tool success tool=\(tool.name) changed=\(response.changedNodeIDs.count)")
            return try self.serializeJSON(response)
        }
    }

    private func connectOrDisconnect(
        arguments: [String: Any],
        bridge: FabricEditorMCPBridge,
        connect: Bool
    ) throws -> MCPBoolResult {
        guard
            let graphIDString = arguments.stringValue(for: "graphID"),
            let graphID = UUID(uuidString: graphIDString),
            let sourceNodeIDString = arguments.stringValue(for: "sourceNode"),
            let sourceNodeID = UUID(uuidString: sourceNodeIDString),
            let sourcePortIDString = arguments.stringValue(for: "sourcePort"),
            let sourcePortID = UUID(uuidString: sourcePortIDString),
            let destinationNodeIDString = arguments.stringValue(for: "destNode"),
            let destinationNodeID = UUID(uuidString: destinationNodeIDString),
            let destinationPortIDString = arguments.stringValue(for: "destinationPort"),
            let destinationPortID = UUID(uuidString: destinationPortIDString)
        else {
            throw FabricEditorMCPBridge.BridgeError.invalidOperation("graphID/sourceNode/sourcePort/destNode/destinationPort are required")
        }

        if connect {
            return bridge.connectNodePortToNodePort(
                graphID: graphID,
                sourceNodeID: sourceNodeID,
                sourcePortID: sourcePortID,
                destinationNodeID: destinationNodeID,
                destinationPortID: destinationPortID
            )
        }

        return bridge.disconnectNodePortToNodePort(
            graphID: graphID,
            sourceNodeID: sourceNodeID,
            sourcePortID: sourcePortID,
            destinationNodeID: destinationNodeID,
            destinationPortID: destinationPortID
        )
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
        if let bool = self[key] as? Bool { return bool }
        if let number = self[key] as? NSNumber { return number.boolValue }
        return nil
    }

    func stringArrayValue(for key: String) -> [String]? {
        guard let raw = self[key] as? [Any] else { return nil }
        return raw.compactMap { $0 as? String }
    }

    func vector2Value(for key: String) -> MCPVector2? {
        guard let raw = self[key] as? [String: Any] else { return nil }
        guard let x = raw["x"] as? Double, let y = raw["y"] as? Double else { return nil }
        return MCPVector2(x: x, y: y)
    }
}
