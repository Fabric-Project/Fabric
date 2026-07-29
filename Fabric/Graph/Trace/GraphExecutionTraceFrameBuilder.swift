//
//  GraphExecutionTraceFrameBuilder.swift
//  Fabric
//
//  Created by Anton Marini on 7/29/26.
//
import Foundation

private final class GraphExecutionTraceFrameBuilder
{
    let executionIndex: Int
    let startedAt: TimeInterval
    var nodeExecutions: [NodeExecution] = []

    init(executionIndex: Int, startedAt: TimeInterval)
    {
        self.executionIndex = executionIndex
        self.startedAt = startedAt
    }

    func makeExecution(endedAt: TimeInterval) -> GraphExecution
    {
        GraphExecution(executionIndex: executionIndex,
                       startedAt: startedAt,
                       endedAt: endedAt,
                       nodeExecutions: nodeExecutions)
    }
}
