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
        /// Visited this pass but sitting it out: every upstream pull declined
        /// (e.g. all inlets hang off unselected Gate branches). Distinct from
        /// .processing so an abandoned pull is never mistaken for a satisfied
        /// node or a feedback back-edge.
        case declined
        case processed
    }

    /// Per-pass node state, indexed by Node.executionSlot and validated by
    /// pass generation: bumping `generation` in resetCacheFor invalidates
    /// every entry at once, with no per-pass allocation or UUID hashing.
    private struct SlotState
    {
        var generation: UInt64 = 0
        var state: NodeProcessingState = .unprocessed
    }

    private var slotStates: [SlotState] = []
    private var generation: UInt64 = 1

    private struct FeedbackCandidate
    {
        let upstreamOutlet: Port
        let upstreamNode: Node
    }

    private let graphID:UUID

    // Previous / current frame port values, swapped on frame change. Writes
    // land in the current buffer; feedback injection reads the previous one.
    private var previousFramePortValues: [UUID: PortValue] = [:]
    private var currentFramePortValues: [UUID: PortValue] = [:]
    private var lastBufferSwapFrameNumber: Int = Int.min

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
        // Invalidate all per-pass node state at once.
        generation &+= 1

        let currentFrame = executionInfo.timing.frameNumber

        if lastBufferSwapFrameNumber != currentFrame
        {
            swap(&previousFramePortValues, &currentFramePortValues)
            currentFramePortValues.removeAll(keepingCapacity: true)
            lastBufferSwapFrameNumber = currentFrame
        }
    }

    func invalidateTopologyCaches()
    {
        feedbackCandidateCache.removeAll(keepingCapacity: true)
        connectedOutputPortCache.removeAll(keepingCapacity: true)
    }

    func processingState(forNode node:Node) -> NodeProcessingState
    {
        let slot = node.executionSlot

        guard slot >= 0, slot < slotStates.count, slotStates[slot].generation == generation
        else { return .unprocessed }

        return slotStates[slot].state
    }

    func setProcessingState(
        _ state: NodeProcessingState,
        forNode node:Node,
        executionInfo:GraphExecutionInfo
    )
    {
        let slot = node.executionSlot
        guard slot >= 0 else { return }

        if slot >= slotStates.count
        {
            slotStates.append(contentsOf: repeatElement(SlotState(), count: slot - slotStates.count + 1))
        }

        slotStates[slot] = SlotState(generation: generation, state: state)

        if state == .processed
        {
            self.cacheProcessedNode(node, executionInfo: executionInfo)
        }
    }

    /// Injects cached previous-frame values into inlets whose upstream node is
    /// currently .processing (a feedback back-edge). The renderer calls this
    /// with each pull's inlets afresh — the active-inlet set can follow
    /// runtime routing values — and only the per-inlet upstream pairing is
    /// cached.
    func injectFeedback(forInlets inlets: [Port], executionInfo: GraphExecutionInfo)
    {
        guard !previousFramePortValues.isEmpty else { return }

        for inlet in inlets
        {
            guard let candidate = feedbackCandidate(forInlet: inlet) else { continue }

            if processingState(forNode: candidate.upstreamNode) == .processing
            {
                if let cached = previousFramePortValues[candidate.upstreamOutlet.id] // PortValue?
                {
                    // This is the critical part: make the inlet read last frame instead of recursing
                    inlet.restoreValue(from: cached)
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
                upstreamNode: upstreamNode
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
        for outlet in connectedOutputPorts(forNode: node)
        {
            if let boxed = outlet.snapshotValue()
            {
                currentFramePortValues[outlet.id] = boxed
            }
            else
            {
                currentFramePortValues.removeValue(forKey: outlet.id)
            }
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
