//
//  GraphRendererFeedbackCache.swift
//  Fabric
//
//  Created by Anton Marini on 12/24/25.
//

import Foundation

/// This Cache holds boxed / type erased values of ports from the last execution frame
/// We then use this Cache if we detect feedback and need to populate inlets of other connected
/// 'downstream' nodes which are also upstream (feedback)

internal final class GraphRendererFeedbackCache
{
    
    // TODO: in theory we can remove the dirty semantics from node?
    public enum NodeProcessingState
    {
        case unprocessed
        case processing
        case processed
    }

    private var nodeProcessingStateCache: [UUID: NodeProcessingState] = [:]
        
    private struct PortCacheKey: Hashable
    {
        let portID: UUID
        let frameNumber: Int
    }

    private let graphID:UUID

    private var lastCachePruneFrameNumber: Int = -1
    private var previousFrameCache: [PortCacheKey: PortValue] = [:]
    
    internal init(graphID:UUID)
    {
        self.graphID = graphID
    }
    
    public func resetCacheFor(executionContext:GraphExecutionContext)
    {
        // Clear execution state
        self.nodeProcessingStateCache = [:]
        
        let currentFrame = executionContext.timing.frameNumber
        let previousFrame = currentFrame - 1

        if self.lastCachePruneFrameNumber != currentFrame
        {
            self.previousFrameCache = previousFrameCache.filter { $0.key.frameNumber == previousFrame }
            self.lastCachePruneFrameNumber = currentFrame
        }
        
//        print("GraphRendererFeedbackCache: resetCacheFor: \(graphID) frame \(currentFrame)")
    }
    
    func processingState(forNode node:Node) -> NodeProcessingState
    {
        return nodeProcessingStateCache[node.id, default: .unprocessed]
    }
    
    func setProcessingState(_ state: NodeProcessingState, forNode node:Node, executionContext:GraphExecutionContext)
    {
        nodeProcessingStateCache[node.id] = state
        
        switch state
        {
        case .unprocessed:
            return
            
        case .processing:
            self.setFeedbackState(forNode: node, executionContext: executionContext)
            
        case .processed:
            self.cacheProcessedNode(node, executionContext: executionContext)
        }
    }
    
    private func setFeedbackState(forNode node:Node, executionContext:GraphExecutionContext)
    {
        let currentFrame = executionContext.timing.frameNumber
        let previousFrame = currentFrame - 1

        // Inject cached previous-frame values for back-edges (upstream node is currently .processing)
        for inlet in node.inputPorts()
        {
            // In Fabric, inlets typically have at most 1 connection; if more, decide policy.
            guard let upstreamOutlet = inlet.connections.first(where: { $0.kind == .Outlet }) else { continue }
            guard let upstreamNode = upstreamOutlet.node else { continue }

            if nodeProcessingStateCache[upstreamNode.id, default: .unprocessed] == .processing
            {
                let key = PortCacheKey(portID: upstreamOutlet.id, frameNumber: previousFrame)
                let cached = previousFrameCache[key] // PortValue?

                // This is the critical part: make the inlet read last frame instead of recursing
                inlet.setBoxedValue(cached)
                
//                print("GraphRendererFeedbackCache: setFeedbackState: \(graphID) frame \(currentFrame) node: \(node.name) inlet port: \(inlet.name)")
            }
        }
    }
    
    private func cacheProcessedNode(_ node: Node, executionContext:GraphExecutionContext)
    {
        let currentFrame = executionContext.timing.frameNumber

        for outlet in node.outputPorts()
        {
            if !outlet.connections.isEmpty
            {
                let key = PortCacheKey(portID: outlet.id, frameNumber: currentFrame)
                
                if let boxed = outlet.boxedValue()
                {
                    previousFrameCache[key] = boxed
                }
                else
                {
                    previousFrameCache.removeValue(forKey: key)
                }
                
//                print("GraphRendererFeedbackCache: cacheProcessedNode: \(graphID) frame \(currentFrame) node: \(node.name) outlet port: \(outlet.name)")

            }
        }
    }
    
}
