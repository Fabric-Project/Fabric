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

    private struct FeedbackCandidate
    {
        let inlet: Port
        let upstreamOutlet: Port
        let upstreamNodeID: UUID
    }

    private struct FeedbackCandidateCacheKey: Hashable
    {
        let nodeID: UUID
        let requestedOutputPortID: UUID?
    }

    private let graphID:UUID

    private var lastCachePruneFrameNumber: Int = -1
    private var previousFrameCache: [PortCacheKey: PortValue] = [:]

    // Resolved inlet -> upstream outlet pairs for feedback checks.
    // Rebuilt when the graph reports a topology change.
    private var feedbackCandidateCache: [FeedbackCandidateCacheKey: [FeedbackCandidate]] = [:]
    private var connectedOutputPortCache: [UUID: [Port]] = [:]
    
    internal init(graphID:UUID)
    {
        self.graphID = graphID
    }
    
    public func resetCacheFor(executionInfo:GraphExecutionInfo)
    {
        // Clear execution state
        self.nodeProcessingStateCache = [:]
        
        let currentFrame = executionInfo.timing.frameNumber
        let previousFrame = currentFrame - 1

        if self.lastCachePruneFrameNumber != currentFrame
        {
            let staleKeys = previousFrameCache.keys.filter { $0.frameNumber < previousFrame }
            for key in staleKeys {
                previousFrameCache.removeValue(forKey: key)
            }
            self.lastCachePruneFrameNumber = currentFrame
        }
        
//        print("GraphRendererFeedbackCache: resetCacheFor: \(graphID) frame \(currentFrame)")
    }

    func invalidateTopologyCaches()
    {
        feedbackCandidateCache.removeAll(keepingCapacity: true)
        connectedOutputPortCache.removeAll(keepingCapacity: true)
    }
    
    func processingState(forNode node:Node) -> NodeProcessingState
    {
        return nodeProcessingStateCache[node.id, default: .unprocessed]
    }
    
    func setProcessingState(
        _ state: NodeProcessingState,
        forNode node:Node,
        requestedOutputPort: Port? = nil,
        executionInfo:GraphExecutionInfo,
        cacheProcessedOutputs: Bool = true
    )
    {
        nodeProcessingStateCache[node.id] = state
        
        switch state
        {
        case .unprocessed:
            return
            
        case .processing:
            self.setFeedbackState(forNode: node,
                                  requestedOutputPort: requestedOutputPort,
                                  executionInfo: executionInfo)
            
        case .processed where cacheProcessedOutputs:
            self.cacheProcessedNode(node, executionInfo: executionInfo)

        case .processed:
            return
        }
    }
        
    private func setFeedbackState(forNode node:Node,
                                  requestedOutputPort: Port?,
                                  executionInfo:GraphExecutionInfo)
    {
        guard !previousFrameCache.isEmpty else { return }

        let previousFrame = executionInfo.timing.frameNumber - 1

        // Inject cached previous-frame values for back-edges (upstream node is currently .processing)
        for candidate in feedbackCandidates(forNode: node, requestedOutputPort: requestedOutputPort)
        {
            if nodeProcessingStateCache[candidate.upstreamNodeID, default: .unprocessed] == .processing
            {
                let key = PortCacheKey(portID: candidate.upstreamOutlet.id, frameNumber: previousFrame)
                if let cached = previousFrameCache[key] // PortValue?
                {
                    // This is the critical part: make the inlet read last frame instead of recursing
                    candidate.inlet.restoreValue(from: cached)
                }
//                print("GraphRendererFeedbackCache: setFeedbackState: \(graphID) node: \(node.name) inlet port: \(candidate.inlet.name)")
            }
        }
    }

    private func feedbackCandidates(forNode node: Node, requestedOutputPort: Port?) -> [FeedbackCandidate]
    {
        let cacheKey = FeedbackCandidateCacheKey(
            nodeID: node.id,
            requestedOutputPortID: requestedOutputPort?.id
        )

        if let cached = feedbackCandidateCache[cacheKey]
        {
            return cached
        }

        let candidates = node.activeInputPorts(requestedOutputPort: requestedOutputPort).compactMap { inlet -> FeedbackCandidate? in
            // In Fabric, inlets typically have at most 1 connection; if more, preserve current first-outlet policy.
            guard let upstreamOutlet = inlet.connections.first(where: { $0.kind == .Outlet }),
                  let upstreamNode = upstreamOutlet.node
            else { return nil }

            return FeedbackCandidate(
                inlet: inlet,
                upstreamOutlet: upstreamOutlet,
                upstreamNodeID: upstreamNode.id
            )
        }

        feedbackCandidateCache[cacheKey] = candidates

        return candidates
    }

    func cacheProcessedNode(_ node: Node, executionInfo:GraphExecutionInfo)
    {
        let currentFrame = executionInfo.timing.frameNumber

        for outlet in connectedOutputPorts(forNode: node)
        {
            let key = PortCacheKey(portID: outlet.id, frameNumber: currentFrame)

            if let boxed = outlet.snapshotValue()
            {
                previousFrameCache[key] = boxed
            }
            else
            {
                previousFrameCache.removeValue(forKey: key)
            }

//            print("GraphRendererFeedbackCache: cacheProcessedNode: \(graphID) frame \(currentFrame) node: \(node.name) outlet port: \(outlet.name)")
        }
    }

    private func connectedOutputPorts(forNode node: Node) -> [Port]
    {
        if let cached = connectedOutputPortCache[node.id]
        {
            return cached
        }

        let connectedOutputs = node.outputPorts().filter { !$0.connections.isEmpty }
        connectedOutputPortCache[node.id] = connectedOutputs
        return connectedOutputs
    }
    
}
