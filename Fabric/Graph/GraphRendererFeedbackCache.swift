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
        /// Declined a pull for an unselected output and had its keep-alive
        /// control inputs pulled. Guards that walk to once per pass and
        /// terminates control chains that cycle back into another unselected
        /// output. Unlike .declined it is not final: a later pull for a live
        /// output upgrades the node to full evaluation.
        case keepAliveWalked
        /// Visited this pass but sitting it out: every upstream pull declined
        /// (e.g. all inlets hang off unselected Gate branches). Distinct from
        /// .processing so an abandoned pull is never mistaken for a satisfied
        /// node or a feedback back-edge.
        case declined
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
        let upstreamOutlet: Port
        let upstreamNodeID: UUID
    }

    private let graphID:UUID

    private var lastCachePruneFrameNumber: Int = -1
    private var previousFrameCache: [PortCacheKey: PortValue] = [:]

    // Resolved inlet -> upstream outlet pairing (nil = unconnected inlet), keyed
    // by inlet ID. Pure topology, so it stays valid however the *set* of active
    // inlets varies with runtime routing values; rebuilt on topology change.
    private var feedbackCandidateCache: [UUID: FeedbackCandidate?] = [:]
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
        activeInputPorts: [Port] = [],
        executionInfo:GraphExecutionInfo,
        cacheProcessedOutputs: Bool = true
    )
    {
        nodeProcessingStateCache[node.id] = state

        switch state
        {
        case .unprocessed, .keepAliveWalked, .declined:
            return

        case .processing:
            self.setFeedbackState(activeInputPorts: activeInputPorts,
                                  executionInfo: executionInfo)

        case .processed where cacheProcessedOutputs:
            self.cacheProcessedNode(node, executionInfo: executionInfo)

        case .processed:
            return
        }
    }

    private func setFeedbackState(activeInputPorts: [Port],
                                  executionInfo:GraphExecutionInfo)
    {
        guard !previousFrameCache.isEmpty else { return }

        let previousFrame = executionInfo.timing.frameNumber - 1

        // Inject cached previous-frame values for back-edges (upstream node is
        // currently .processing). The active-inlet set can follow runtime
        // routing values, so the renderer passes each pull's inlets afresh;
        // only the per-inlet upstream pairing is cached.
        for inlet in activeInputPorts
        {
            guard let candidate = feedbackCandidate(forInlet: inlet) else { continue }

            if nodeProcessingStateCache[candidate.upstreamNodeID, default: .unprocessed] == .processing
            {
                let key = PortCacheKey(portID: candidate.upstreamOutlet.id, frameNumber: previousFrame)
                if let cached = previousFrameCache[key] // PortValue?
                {
                    // Make the inlet read last frame instead of recursing,
                    // using normal send semantics so unchanged feedback does not dirty the node.
                    inlet.sendBoxed(cached, force: false)
                }
            }
        }
    }

    private func feedbackCandidate(forInlet inlet: Port) -> FeedbackCandidate?
    {
        if let cached = feedbackCandidateCache[inlet.id]
        {
            return cached
        }

        // In Fabric, inlets typically have at most 1 connection; if more, preserve current first-outlet policy.
        let candidate: FeedbackCandidate?
        if let upstreamOutlet = inlet.connections.first(where: { $0.kind == .Outlet }),
           let upstreamNode = upstreamOutlet.node
        {
            candidate = FeedbackCandidate(
                upstreamOutlet: upstreamOutlet,
                upstreamNodeID: upstreamNode.id
            )
        }
        else
        {
            candidate = nil
        }

        feedbackCandidateCache[inlet.id] = candidate
        return candidate
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
