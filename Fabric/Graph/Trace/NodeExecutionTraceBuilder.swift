//
//  NodeExecutionTraceBuilder.swift
//  Fabric
//
//  Created by Anton Marini on 7/29/26.
//

import Foundation

private final class NodeExecutionTraceBuilder
{
    let nodeID: UUID
    let nodeName: String
    let nodeTypeName: String
    let orderIndex: Int
    let startedAt: TimeInterval
    var childExecutions: [GraphExecution] = []

    init(node: Node, orderIndex: Int, startedAt: TimeInterval)
    {
        self.nodeID = node.id
        self.nodeName = node.name
        self.nodeTypeName = String(describing: type(of: node))
        self.orderIndex = orderIndex
        self.startedAt = startedAt
    }

    func makeNodeExecution(endedAt: TimeInterval, result: NodeExecutionResult) -> NodeExecution
    {
        NodeExecution(nodeID: nodeID,
                      nodeName: nodeName,
                      nodeTypeName: nodeTypeName,
                      orderIndex: orderIndex,
                      startedAt: startedAt,
                      endedAt: endedAt,
                      result: result,
                      childExecutions: childExecutions)
    }
}
