//
//  GraphExecutionTrace.swift
//  Fabric
//

import Foundation

public struct GraphExecutionTrace: Codable
{
    public let graphID: UUID
    public var executions: [GraphExecution]

    public init(graphID: UUID, executions: [GraphExecution] = [])
    {
        self.graphID = graphID
        self.executions = executions
    }
}
