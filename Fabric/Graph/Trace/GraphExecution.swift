//
//  GraphExecution.swift
//  Fabric
//

import Foundation

public struct GraphExecution: Codable
{
    public let executionIndex: Int
    public let startedAt: TimeInterval
    public let endedAt: TimeInterval
    public var nodeExecutions: [NodeExecution]

    public init(executionIndex: Int,
                startedAt: TimeInterval,
                endedAt: TimeInterval,
                nodeExecutions: [NodeExecution] = [])
    {
        self.executionIndex = executionIndex
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.nodeExecutions = nodeExecutions
    }
}
