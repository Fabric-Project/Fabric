//
//  NodeExecution.swift
//  Fabric
//

import Foundation

public struct NodeExecution: Codable
{
    public let nodeID: UUID
    public let nodeName: String
    public let nodeTypeName: String
    public let orderIndex: Int
    public let startedAt: TimeInterval
    public let endedAt: TimeInterval
    public let result: NodeExecutionResult
    public var childExecutions: [GraphExecution]

    public init(nodeID: UUID,
                nodeName: String,
                nodeTypeName: String,
                orderIndex: Int,
                startedAt: TimeInterval,
                endedAt: TimeInterval,
                result: NodeExecutionResult,
                childExecutions: [GraphExecution] = [])
    {
        self.nodeID = nodeID
        self.nodeName = nodeName
        self.nodeTypeName = nodeTypeName
        self.orderIndex = orderIndex
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.result = result
        self.childExecutions = childExecutions
    }
}
