import Foundation
import XCTest

#if canImport(Fabric_Editor)
@testable import Fabric_Editor
import Fabric

final class FabricEditorMCPToolFlowTests: XCTestCase {
    func testDocumentToolsReturnGraphIDs() async throws {
        let newDocumentResponse = try await self.callTool(
            .makeNewDocument,
            arguments: [:],
            as: MCPGraphIDResponse.self
        )
        XCTAssertNotNil(UUID(uuidString: newDocumentResponse.graphID))

        let activeGraphResponse = try await self.callTool(
            .getActiveDocumentGraph,
            arguments: [:],
            as: MCPGraphIDResponse.self
        )
        XCTAssertEqual(newDocumentResponse.graphID, activeGraphResponse.graphID)
    }

    func testRegistryToolsReturnData() async throws {
        let nodeTypes = try await self.callTool(
            .getAvailableNodeTypes,
            arguments: [:],
            as: [String].self
        )
        XCTAssertFalse(nodeTypes.isEmpty)

        let classNames = try await self.callTool(
            .getAllAvailableNodeClassNames,
            arguments: [:],
            as: [String].self
        )
        XCTAssertFalse(classNames.isEmpty)

        let classInfo = try await self.callTool(
            .getNodeClassInfo,
            arguments: ["nodeName": classNames[0]],
            as: MCPNodeClassInfoResponse?.self
        )
        XCTAssertNotNil(classInfo)
    }

    func testGraphNodeLifecycleTools() async throws {
        let graphID = try await self.makeNewGraphID()

        let classNames = try await self.callTool(
            .getAllAvailableNodeClassNames,
            arguments: [:],
            as: [String].self
        )

        let nodeClass = try await self.findInstantiableNodeClass(graphID: graphID, classNames: classNames)
        let instantiated = try await self.callTool(
            .instantiateNodeClass,
            arguments: [
                "graphID": graphID.uuidString,
                "nodeClass": nodeClass,
            ],
            as: MCPBoolResult.self
        )
        XCTAssertTrue(instantiated.success, instantiated.error ?? "Unknown instantiate error")

        let nodes = try await self.callTool(
            .getInstantiatedGraphNodes,
            arguments: [
                "graphID": graphID.uuidString,
                "includePorts": true,
                "includeDescriptions": false,
            ],
            as: [MCPNodeInfoResponse].self
        )
        XCTAssertFalse(nodes.isEmpty)
        let createdNode = try XCTUnwrap(nodes.last)
        let createdNodeID = try XCTUnwrap(UUID(uuidString: createdNode.nodeID))

        let moved = try await self.callTool(
            .moveNodeToOffset,
            arguments: [
                "graphID": graphID.uuidString,
                "nodeID": createdNodeID.uuidString,
                "offset": ["x": 222.0, "y": 333.0],
            ],
            as: MCPBoolResult.self
        )
        XCTAssertTrue(moved.success, moved.error ?? "Move failed")

        let nodeInfo = try await self.callTool(
            .getNodeInfo,
            arguments: [
                "graphID": graphID.uuidString,
                "nodeID": createdNodeID.uuidString,
            ],
            as: MCPNodeInfoResponse.self
        )
        XCTAssertEqual(nodeInfo.nodeID, createdNodeID.uuidString)

        let deleted = try await self.callTool(
            .deleteNode,
            arguments: [
                "graphID": graphID.uuidString,
                "nodeID": createdNodeID.uuidString,
            ],
            as: MCPBoolResult.self
        )
        XCTAssertTrue(deleted.success, deleted.error ?? "Delete failed")
    }

    func testParameterReadWriteTools() async throws {
        let graphID = try await self.makeNewGraphID()
        let classNames = try await self.callTool(
            .getAllAvailableNodeClassNames,
            arguments: [:],
            as: [String].self
        )

        let target = try await self.findParameterPort(graphID: graphID, classNames: classNames)
        let initialRead = target.readResponse

        let writeValue = self.nextWriteValue(portType: target.portType, currentValue: initialRead.value)
        let writeResponse = try await self.callTool(
            .writeParameterPortValue,
            arguments: [
                "graphID": graphID.uuidString,
                "nodeID": target.nodeID.uuidString,
                "portID": target.portID.uuidString,
                "portValue": writeValue,
            ],
            as: MCPBoolResult.self
        )
        XCTAssertTrue(writeResponse.success, writeResponse.error ?? "Write failed")

        let secondRead = try await self.callTool(
            .readParameterPortValue,
            arguments: [
                "graphID": graphID.uuidString,
                "nodeID": target.nodeID.uuidString,
                "portID": target.portID.uuidString,
            ],
            as: MCPParameterPortValueResponse.self
        )
        XCTAssertEqual(secondRead.portType, target.portType)
        XCTAssertNotNil(secondRead.value)
    }
    
    func testToolingHintsToolReturnsCanonicalGuidance() async throws {
        let hints = try await self.callTool(
            .getToolingHints,
            arguments: [:],
            as: MCPToolingHintsResponse.self
        )
        
        XCTAssertFalse(hints.canonicalFlows.isEmpty)
        XCTAssertFalse(hints.parameterWriteRules.isEmpty)
        XCTAssertFalse(hints.compactPayloadDefaults.isEmpty)
        XCTAssertFalse(hints.graphChangeRules.isEmpty)
    }
    
    func testGraphChangesToolTracksRevisionAndMutations() async throws {
        let graphID = try await self.makeNewGraphID()
        
        let initial = try await self.callTool(
            .getGraphChanges,
            arguments: ["graphID": graphID.uuidString],
            as: MCPGraphChangesResponse.self
        )
        XCTAssertEqual(initial.graphID, graphID.uuidString)
        XCTAssertTrue(initial.revisionToken.hasPrefix("r"))
        
        let unchanged = try await self.callTool(
            .getGraphChanges,
            arguments: [
                "graphID": graphID.uuidString,
                "sinceRevisionToken": initial.revisionToken,
            ],
            as: MCPGraphChangesResponse.self
        )
        XCTAssertEqual(unchanged.revisionToken, initial.revisionToken)
        XCTAssertTrue(unchanged.changedNodeIDs.isEmpty)
        XCTAssertTrue(unchanged.addedNodeIDs.isEmpty)
        XCTAssertTrue(unchanged.removedNodeIDs.isEmpty)
        
        let classNames = try await self.callTool(
            .getAllAvailableNodeClassNames,
            arguments: [:],
            as: [String].self
        )
        let nodeClass = try await self.findInstantiableNodeClass(graphID: graphID, classNames: classNames)
        let instantiate = try await self.callTool(
            .instantiateNodeClass,
            arguments: [
                "graphID": graphID.uuidString,
                "nodeClass": nodeClass,
            ],
            as: MCPBoolResult.self
        )
        XCTAssertTrue(instantiate.success)
        
        let changed = try await self.callTool(
            .getGraphChanges,
            arguments: [
                "graphID": graphID.uuidString,
                "sinceRevisionToken": unchanged.revisionToken,
            ],
            as: MCPGraphChangesResponse.self
        )
        XCTAssertNotEqual(changed.revisionToken, unchanged.revisionToken)
        XCTAssertFalse(changed.addedNodeIDs.isEmpty && changed.changedNodeIDs.isEmpty)
    }

    private func makeNewGraphID() async throws -> UUID {
        let response = try await self.callTool(
            .makeNewDocument,
            arguments: [:],
            as: MCPGraphIDResponse.self
        )
        return try XCTUnwrap(UUID(uuidString: response.graphID))
    }

    private func findInstantiableNodeClass(graphID: UUID, classNames: [String]) async throws -> String {
        for className in classNames {
            let result = try await self.callTool(
                .instantiateNodeClass,
                arguments: [
                    "graphID": graphID.uuidString,
                    "nodeClass": className,
                ],
                as: MCPBoolResult.self
            )
            if result.success {
                return className
            }
        }

        XCTFail("No instantiable node class found")
        throw NSError(domain: "FabricEditorMCPToolFlowTests", code: 1)
    }

    private func findParameterPort(graphID: UUID, classNames: [String]) async throws -> (
        nodeID: UUID,
        portID: UUID,
        portType: String,
        readResponse: MCPParameterPortValueResponse
    ) {
        var previousNodeIDs = Set<UUID>()
        let initialNodes = try await self.callTool(
            .getInstantiatedGraphNodes,
            arguments: [
                "graphID": graphID.uuidString,
                "includePorts": true,
                "includeDescriptions": false,
            ],
            as: [MCPNodeInfoResponse].self
        )
        previousNodeIDs.formUnion(initialNodes.compactMap { UUID(uuidString: $0.nodeID) })

        for className in classNames {
            let instantiateResult = try await self.callTool(
                .instantiateNodeClass,
                arguments: [
                    "graphID": graphID.uuidString,
                    "nodeClass": className,
                ],
                as: MCPBoolResult.self
            )
            guard instantiateResult.success else { continue }

            let nodes = try await self.callTool(
                .getInstantiatedGraphNodes,
                arguments: [
                    "graphID": graphID.uuidString,
                    "includePorts": true,
                    "includeDescriptions": false,
                ],
                as: [MCPNodeInfoResponse].self
            )

            let addedNode = nodes.first {
                guard let id = UUID(uuidString: $0.nodeID) else { return false }
                return !previousNodeIDs.contains(id)
            }
            previousNodeIDs.formUnion(nodes.compactMap { UUID(uuidString: $0.nodeID) })

            guard let addedNode else { continue }
            guard let nodeID = UUID(uuidString: addedNode.nodeID) else { continue }

            for inputPort in addedNode.inputPorts {
                guard let portID = UUID(uuidString: inputPort.portID) else { continue }
                do {
                    let readResponse = try await self.callTool(
                        .readParameterPortValue,
                        arguments: [
                            "graphID": graphID.uuidString,
                            "nodeID": nodeID.uuidString,
                            "portID": portID.uuidString,
                        ],
                        as: MCPParameterPortValueResponse.self
                    )
                    return (nodeID, portID, readResponse.portType, readResponse)
                } catch {
                    continue
                }
            }
        }

        XCTFail("No parameter port found for read/write testing")
        throw NSError(domain: "FabricEditorMCPToolFlowTests", code: 2)
    }

    private func nextWriteValue(portType: String, currentValue: MCPJSONValue?) -> Any {
        switch portType {
        case "Bool":
            if case .bool(let value)? = currentValue { return !value }
            return true
        case "Int":
            if case .int(let value)? = currentValue { return value + 1 }
            if case .double(let value)? = currentValue { return Int(value) + 1 }
            return 1
        case "Float":
            if case .double(let value)? = currentValue { return value + 0.5 }
            if case .int(let value)? = currentValue { return Double(value) + 0.5 }
            return 0.5
        case "String":
            if case .string(let value)? = currentValue { return value + " test" }
            return "test"
        case "Vector 2":
            return [0.5, 1.5]
        case "Vector 3":
            return [0.5, 1.5, 2.5]
        case "Vector 4", "Color", "Quaternion":
            return [0.5, 1.5, 2.5, 3.5]
        case "Transform":
            return Array(repeating: 0.0, count: 16)
        default:
            if portType.hasPrefix("Array of Bool") { return [true, false] }
            if portType.hasPrefix("Array of Int") { return [1, 2, 3] }
            if portType.hasPrefix("Array of Float") { return [1.0, 2.0, 3.0] }
            if portType.hasPrefix("Array of String") { return ["a", "b"] }
            return 0
        }
    }

    private func callTool<Response: Decodable>(
        _ tool: Fabric_Editor.FabricMCPTool,
        arguments: [String: Any],
        as responseType: Response.Type
    ) async throws -> Response {
        let data = try JSONSerialization.data(withJSONObject: arguments, options: [])
        let argumentsJSON = try XCTUnwrap(String(data: data, encoding: String.Encoding.utf8))

        let responseString: String = try await MainActor.run {
            try FabricEditorMCPToolExecutor.shared.callTool(tool: tool, argumentsJSON: argumentsJSON)
        }

        let responseData = try XCTUnwrap(responseString.data(using: String.Encoding.utf8))
        return try JSONDecoder().decode(responseType, from: responseData)
    }
}

#endif
