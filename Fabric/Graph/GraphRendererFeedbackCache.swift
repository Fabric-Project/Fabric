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

internal final class GraphRendererFeedbackCache {
    
    // TODO: in theory we can remove the dirty semantics from node?
    public enum NodeProcessingState
    {
        case unprocessed
        case processing
        case processed
    }

    private var nodeProcessingStateCache: [UUID: NodeProcessingState] = [:]
        
    private var nodeProcessingStateStack: [[UUID: NodeProcessingState]] = []

    private struct PortCacheKey: Hashable
    {
        let portID: UUID
        let frameNumber: Int
    }

    private var lastCachePruneFrameNumber: Int = -1
    private var previousFrameCache: [PortCacheKey: PortValue] = [:]
    
    /// Call at the start of every execute() (including nested subgraph executes).
    /// This isolates nodeProcessingStateCache so nested executes don't clobber the caller's traversal.
    public func beginExecutionScope(executionContext: GraphExecutionContext)
    {
        
        // 1) prune port cache once per frame (shared across scopes)
        let currentFrame = executionContext.timing.frameNumber
        let previousFrame = currentFrame - 1
        
        if self.lastCachePruneFrameNumber != currentFrame
        {
            self.previousFrameCache = previousFrameCache.filter { $0.key.frameNumber == previousFrame }
            self.lastCachePruneFrameNumber = currentFrame
        }
        
        // 2) isolate processing state (per-scope)
        nodeProcessingStateStack.append(nodeProcessingStateCache)
        nodeProcessingStateCache = [:]
        
        print("frameCache beginExecutionScope frame: \(currentFrame)")
    }
    
    /// Must be paired with beginExecutionScope via defer.
    public func endExecutionScope()
    {
        guard let restored = nodeProcessingStateStack.popLast()
        else
        {
            // If this ever happens, someone called end without begin.
            nodeProcessingStateCache = [:]
            return
        }
        
        nodeProcessingStateCache = restored
        
        print("frameCache endExecutionScope")

    }
    
//    public func resetCacheFor(executionContext:GraphExecutionContext)
//    {
//        self.nodeProcessingStateCache = [:]
//        
//        let currentFrame = executionContext.timing.frameNumber
//        let previousFrame = currentFrame - 1
//
//        if self.lastCachePruneFrameNumber != currentFrame
//        {
//            self.previousFrameCache = previousFrameCache.filter { $0.key.frameNumber == previousFrame }
//            self.lastCachePruneFrameNumber = currentFrame
//        }
//    }
    
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
                
                let hit = (cached != nil)
                print("setFeedbackState Frame: \(currentFrame), Upstream: \(upstreamNode.name):\(upstreamOutlet.name), ID: \(upstreamOutlet.id) hit: \(hit)")

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
                
                let hit = (outlet.boxedValue() != nil)
                
                if let boxed = outlet.boxedValue()
                {
                    previousFrameCache[key] = boxed
                }
                else
                {
                    previousFrameCache.removeValue(forKey: key)
                }
                
                print("cacheProcessedNode Frame: \(currentFrame), Outlet: \(node.name):\(outlet.name), ID: \(outlet.id) boxedValueNonNil: \(hit)")

            }
        }
    }
    
}
