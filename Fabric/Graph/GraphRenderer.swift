//
//  GraphExecution.swift
//  v
//
//  Created by Anton Marini on 4/27/24.
//

import SwiftUI
import Metal
import Satin

// Graph Execution Engine
public class GraphRenderer : ViewRenderer
{
    public let renderEncoder:RenderEncoder
    private let traceEditorExecution = false

    override public var sampleCount: Int { self.context.sampleCount }
    override public var colorPixelFormat: MTLPixelFormat { self.context.colorPixelFormat }
    override public var depthPixelFormat: MTLPixelFormat { self.context.depthPixelFormat }
    override public var stencilPixelFormat: MTLPixelFormat { self.context.stencilPixelFormat }

    public var executionCount = 0
    public private(set) var executionTrace: GraphExecutionTrace?
    {
        didSet { isTracingExecution = executionTrace != nil }
    }
    // Checked per node per iteration; cheaper than testing the Optional trace each time.
    private var isTracingExecution = false

    public private(set) var currentExecutionInfo: GraphExecutionInfo = GraphExecutionInfo(
        timing: .zero
    )

    public private(set) var currentCamera: Camera? = nil
    private let defaultCamera: PerspectiveCamera

    /// This frame's Satin submission, made the first time a node records into it (an Iterator).
    private var pendingSubmission: SubmissionBuilder?
    private var submissionScopeDepth = 0
    internal private(set) var deferredGPUResults: GraphDeferredResults?
    private let sceneProxy: Object

    // Regular subgraphs execute by re-entering execute(graph:) on this renderer.
    // Only the outermost call selects the camera for the scene that will draw;
    // nested executions must not replace it with their own cached selection.
    private var isExecutingGraph = false

    // Staging slot for external event injection (e.g. input event handlers).
    // update() drains this into currentExecutionInfo each frame.
    public var pendingEventInfo: GraphEventInfo? = nil

    private var graphRequiresResize: Bool = false
    public private(set) var resizeScaleFactor: Float = 1.0

    private var executionPlanCaches: [ObjectIdentifier: GraphExecutionPlanCache] = [:]
    // Iterator executes the same graph many times a frame; skip hashing for a repeat.
    private var lastExecutionPlan: GraphExecutionPlanCache?
    private var traceExecutionIndex = 0
    private var graphExecutionTraceStack: [GraphExecutionTraceFrameBuilder] = []
    private var nodeExecutionTraceStack: [NodeExecutionTraceBuilder] = []

    public let graph: Graph

    // The lifecycle this renderer asks of the graphs it runs. Each node reports
    // the lifecycle it has actually reached through its own executionState.
    public private(set) var executionState: ExecutionState = .disabled

    public init(context: Context, graph: Graph)
    {
        self.graph = graph
        self.renderEncoder = RenderEncoder(
            context: context,
            clearColor: .zero,
            depthStoreAction: .store,
            stencilStoreAction: .dontCare,
            frameBufferOnly: false
        )

        self.renderEncoder.sortObjects = true

        self.sceneProxy = Object(context: context)
        // The camera a graph gets for free is the camera node's, at its
        // defaults, so adding that node to a graph reframes nothing.
        self.defaultCamera = PerspectiveCameraNode.makeDefaultCamera(context: context)

        super.init(context: context)
    }

    // MARK: - Satin ViewRenderer Lifecycle

    override public func setup() throws {
        try super.setup()

        // Starting enables each node first, and one failing node does not keep the rest from starting.
        try startExecution(trace: traceEditorExecution)
    }

    override public func update(frame: FrameTime) throws {
        try super.update(frame: frame)

        currentExecutionInfo = GraphExecutionInfo(timing: frame, eventInfo: pendingEventInfo)
        pendingEventInfo = nil
    }

#if os(macOS)
    // MARK: - Input Events

    // Satin's MetalViewController pushes AppKit events at the renderer as they
    // happen. Only the events Cursor and Keyboard nodes consume are staged;
    // the slot is drained once per frame in update(), so when several arrive
    // between frames the newest wins. Delivery and update() share the main
    // thread (the display link runs on the main run loop), so no locking.
    private func stageEventForNextExecution(_ event: NSEvent)
    {
        self.pendingEventInfo = GraphEventInfo(event: event)
    }

    override public func mouseMoved(with event: NSEvent) { self.stageEventForNextExecution(event) }
    override public func mouseDown(with event: NSEvent) { self.stageEventForNextExecution(event) }
    override public func mouseDragged(with event: NSEvent) { self.stageEventForNextExecution(event) }
    override public func mouseUp(with event: NSEvent) { self.stageEventForNextExecution(event) }
    override public func rightMouseDown(with event: NSEvent) { self.stageEventForNextExecution(event) }
    override public func rightMouseDragged(with event: NSEvent) { self.stageEventForNextExecution(event) }
    override public func rightMouseUp(with event: NSEvent) { self.stageEventForNextExecution(event) }
    override public func otherMouseDown(with event: NSEvent) { self.stageEventForNextExecution(event) }
    override public func otherMouseDragged(with event: NSEvent) { self.stageEventForNextExecution(event) }
    override public func otherMouseUp(with event: NSEvent) { self.stageEventForNextExecution(event) }

    // Not reported as handled: the graph observes keys, it does not own them,
    // so the responder chain carries on as it did before.
    override public func keyDown(with event: NSEvent) -> Bool
    {
        self.stageEventForNextExecution(event)
        return false
    }

    override public func keyUp(with event: NSEvent) -> Bool
    {
        self.stageEventForNextExecution(event)
        return false
    }

#elseif os(iOS)
    // MARK: - Input Events

    // Satin's MetalViewController pushes UIKit touch events at the renderer
    // as they happen, mirroring the macOS AppKit path above. The slot is
    // drained once per frame in update(), so when several arrive between
    // frames the newest wins. Delivery and update() share the main thread
    // (the display link runs on the main run loop), so no locking.
    private func stageEventForNextExecution(_ event: UIEvent?)
    {
        self.pendingEventInfo = GraphEventInfo(event: event)
    }

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { self.stageEventForNextExecution(event) }
    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { self.stageEventForNextExecution(event) }
    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { self.stageEventForNextExecution(event) }
    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { self.stageEventForNextExecution(event) }
#endif

    /// Set the execution info without reading the wall clock. Tests call this
    /// directly to drive the update/draw path with deterministic timing.
    func planFrame(executionInfo: GraphExecutionInfo) {
        currentExecutionInfo = executionInfo
    }

    override public func cleanup() throws {
        let traceURL = URL(fileURLWithPath: "/private/tmp")
            .appending(path: "fabric-graph-execution-trace-\(graph.id).json")
        // Every phase runs even when an earlier one fails; the first failure is rethrown.
        var capturedError: (any Error)?
        do { try stopExecution(saveTraceTo: traceEditorExecution ? traceURL : nil) }
        catch { capturedError = error }
        do { try disableExecution() }
        catch { if capturedError == nil { capturedError = error } }
        teardown()
        do { try super.cleanup() }
        catch { if capturedError == nil { capturedError = error } }
        // Torn-down nodes no longer hold their images: give the now-empty heaps back. Heaps still
        // used by in-flight GPU work or other renderers sharing the allocator are kept.
        context.gpuAllocator.trim(retainingEmptyHeaps: 0)

        if let capturedError
        {
            throw capturedError
        }
    }

    override public func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        self.renderEncoder.resize(size)
        self.graphRequiresResize = true
        self.resizeScaleFactor = scaleFactor
        // Field of view is the camera's, not the drawable's: a resize changes
        // the resolution rendered and how much is visible to the sides, and
        // must not change the framing of what a graph was authored against.
        self.defaultCamera.aspect = size.width / size.height
    }

    // MARK: - Draw

    override public func preDraw() -> MTLCommandBuffer? {
        let batch = admitDeferredFrame()
        guard let commandBuffer = super.preDraw() else {
            batch?.finishRecording()
            return nil
        }
        let commands = GraphCommandBuffer(commandBuffer: commandBuffer)
        commands.graphRenderer = self
        commands.deferredBatch = batch
        return commands
    }

    /// For offscreen callers. Use the same stable MPS wrapper as the display-driven path.
    public func makeCommandBuffer() -> MTLCommandBuffer? {
        let batch = admitDeferredFrame()
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            batch?.finishRecording()
            return nil
        }
        let commands = GraphCommandBuffer(commandBuffer: commandBuffer)
        commands.graphRenderer = self
        commands.deferredBatch = batch
        return commands
    }

    internal func ensureDeferredResults() -> GraphDeferredResults {
        if let deferredGPUResults { return deferredGPUResults }
        let results = GraphDeferredResults(limit: context.maxBuffersInFlight)
        deferredGPUResults = results
        return results
    }

    private func reportDeferredErrors(_ results: GraphDeferredResults) {
        for error in results.takeErrors() { errorDelegate?.renderer(self, didFailWith: error) }
    }

    private func admitDeferredFrame() -> GraphDeferredFrameBatch? {
        guard let deferredGPUResults else { return nil }
        let batch = deferredGPUResults.admit()
        reportDeferredErrors(deferredGPUResults)
        return batch
    }

    private func prepareDeferredExecution(_ commandBuffer: MTLCommandBuffer) {
        guard let commands = commandBuffer as? GraphCommandBuffer else { return }
        if commands.graphRenderer == nil { commands.graphRenderer = self }
        guard commands.executingNode == nil,
              let owner = commands.graphRenderer, let results = owner.deferredGPUResults else { return }
        if commands.deferredBatch == nil { commands.deferredBatch = results.admit() }
        else { results.processReady() }
        owner.reportDeferredErrors(results)
    }

    override public func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        do
        {
            try executeAndDraw(executionInfo: currentExecutionInfo,
                               renderPassDescriptor: renderPassDescriptor,
                               commandBuffer: commandBuffer)
        }
        catch
        {
            // Reported rather than thrown, so Satin still presents the drawn frame.
            guard error.isRecoverable else { throw error }
            errorDelegate?.renderer(self, didFailWith: error)
        }
    }

    // MARK: - Frame submission

    /// The submission this frame's records go into, made on first use from the current camera and
    /// this renderer's settings as they are then. Satin freezes both when it's made: a camera node,
    /// or a node changing the renderer's settings, that runs after the first record takes effect the
    /// next frame. (Camera nodes are to run first.) Record with `record(scene:)` after updating and
    /// encoding the scene; the graph's own scene is recorded and the frame drawn after execution.
    public func frameSubmission(frame: FrameTime) -> SubmissionBuilder
    {
        if let pendingSubmission { return pendingSubmission }
        let submission = self.renderEncoder.makeSubmissionBuilder(frame: frame,
                                                                  cameras: [self.currentCamera ?? self.defaultCamera],
                                                                  viewports: [self.renderEncoder.viewport])
        self.pendingSubmission = submission
        return submission
    }

    // Nested graph/Iterator evaluations contribute to the enclosing draw. Standalone
    // evaluation owns a temporary scope instead: its records cannot escape to a later draw.
    private func beginSubmissionScope() {
        if submissionScopeDepth == 0 { pendingSubmission = nil }
        submissionScopeDepth += 1
    }

    private func endSubmissionScope() {
        submissionScopeDepth -= 1
        if submissionScopeDepth == 0 { pendingSubmission = nil }
    }

    // MARK: - On-demand graph evaluation (for exporters and subgraph callers)

    public func executeAndDraw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        try executeAndDraw(executionInfo: currentExecutionInfo, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }

    public func executeAndDraw(executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        try validateContinuationOwnership(commandBuffer)
        prepareDeferredExecution(commandBuffer)
        beginSubmissionScope()
        defer { endSubmissionScope() }
        let clearColor = self.renderEncoder.clearColor
        let colorLoadAction = self.renderEncoder.colorLoadAction
        let depthLoadAction = self.renderEncoder.depthLoadAction
        let stencilLoadAction = self.renderEncoder.stencilLoadAction
        defer {
            self.renderEncoder.clearColor = clearColor
            self.renderEncoder.colorLoadAction = colorLoadAction
            self.renderEncoder.depthLoadAction = depthLoadAction
            self.renderEncoder.stencilLoadAction = stencilLoadAction
        }

        let needsSceneSync = graph.consumePendingConnectionSceneSync()

        // A node added since the last drawable resize has never been given the
        // size, and a camera added that way would project through Satin's
        // square default aspect — the scene stretched to the target's shape.
        // A change in the graph's topology is the signal that someone in it
        // has yet to be told.
        if needsSceneSync
        {
            self.graphRequiresResize = true
        }

        var recoverableError: (any Error)?
        do
        {
            try self.execute(graph: graph,
                             executionInfo: executionInfo,
                             renderPassDescriptor: renderPassDescriptor,
                             commandBuffer: commandBuffer)
        }
        catch
        {
            guard error.isRecoverable else { throw error }
            recoverableError = error
        }

        if needsSceneSync {
            graph.syncNodesToScene()
        }

        if let submission = self.pendingSubmission
        {
            // Iterator records come first; the graph's scene, recorded now, draws ahead of them per layer.
            self.pendingSubmission = nil
            try submission.record(scene: graph.scene,
                                  renderPassDescriptor: renderPassDescriptor,
                                  preparationCommandBuffer: commandBuffer)
            try submission.seal().encode(into: commandBuffer)
        }
        else
        {
            try self.renderEncoder.draw(frame: executionInfo.timing,
                                        renderPassDescriptor: renderPassDescriptor,
                                        commandBuffer: commandBuffer,
                                        scene: graph.scene,
                                        camera: self.currentCamera ?? self.defaultCamera)
        }

        self.executionCount += 1

        // The frame is drawn; the caller still learns the pass failed.
        if let recoverableError
        {
            throw recoverableError
        }
    }

    /// Evaluate without drawing this graph's scene. Iterator records belong to the enclosing
    /// executeAndDraw call, if any; standalone evaluation discards them on return or failure.
    public func execute(graph: Graph,
                        executionInfo: GraphExecutionInfo,
                        renderPassDescriptor: MTLRenderPassDescriptor,
                        commandBuffer: MTLCommandBuffer,
                        clearFlags: Bool = true,
                        forceEvaluationForTheseNodes: [Node] = []) throws
    {
        try validateContinuationOwnership(commandBuffer)
        prepareDeferredExecution(commandBuffer)
        beginSubmissionScope()
        defer { endSubmissionScope() }

        defer {
            if clearFlags {
                self.graphRequiresResize = false
            }
        }

        let isOutermostExecution = !self.isExecutingGraph
        if isOutermostExecution
        {
            do { try synchronizeLifecycle() }
            catch { errorDelegate?.renderer(self, didFailWith: error) }

            self.currentCamera = graph.latestCamera ?? self.defaultCamera
        }

        self.isExecutingGraph = true
        defer
        {
            if isOutermostExecution
            {
                self.isExecutingGraph = false
            }
        }

        var capturedError: (any Error)?
        let scheduledNodes = executionPlan(for: graph).scheduledNodes(forcing: forceEvaluationForTheseNodes)

        let graphTraceFrame = beginGraphExecutionTrace()
        let commands = commandBuffer as? GraphCommandBuffer

        for (orderIndex, node) in scheduledNodes.enumerated() {
            if self.graphRequiresResize {
                node.resize(size: self.renderEncoder.size, scaleFactor: self.resizeScaleFactor)
            }

            // Sized even while stopped: the resize flag clears after this pass.
            guard node.executionState == .started else { continue }

            let nodeTrace = beginNodeExecutionTrace(node: node, orderIndex: orderIndex)
            let enclosingNode = commands?.executingNode
            commands?.executingNode = node
            defer { commands?.executingNode = enclosingNode }
            var hasDeferredDelivery = false
            var deferredState: GraphDeferredNodeState?
            if let binding = node.deferredResultsBinding, let commands {
                let state = commands.resultScope().state(for: binding)
                deferredState = state
                hasDeferredDelivery = state.hasPreparedDelivery
                state.publish(binding: binding)
                if state.needsRetry {
                    state.needsRetry = false
                    node.markDirty()
                    // Re-evaluate once after abandonment, including nodes whose work is guarded
                    // by inlet changes. Only async-participating contexts enter this path.
                    for input in node.inputPorts() { input.valueDidChange = true }
                }
            }

            guard hasDeferredDelivery || node.isDirty || node.nodeExecutionMode == .Consumer || node.nodeExecutionMode == .Provider else {
                endNodeExecutionTrace(nodeTrace, result: .skippedClean)
                continue
            }

#if DEBUG
            commandBuffer.pushDebugGroup(node.debugDescription)
#endif
            var executionError: (any Error)?
            node.hasPendingExecutionCleanup = true
            if let deferredState { node.deferredResultsBinding?.beginExecution(in: deferredState) }

            do
            {
                try node.execute(renderer: self,
                                 executionInfo: executionInfo,
                                 renderPassDescriptor: renderPassDescriptor,
                                 commandBuffer: commandBuffer)
            }
            catch
            {
                executionError = error
            }
            node.deferredResultsBinding?.endExecution()
#if DEBUG
            commandBuffer.popDebugGroup()
#endif

            endNodeExecutionTrace(nodeTrace, result: executionError == nil ? .executed : .error)

            if clearFlags {
                node.markClean()
            }

            // Failures are isolated to the node that threw: the pass keeps
            // going and the first error is rethrown once it completes. Stopping
            // here instead would skip every node scheduled later, and their
            // flags would then be cleared anyway by an ancestor's markClean
            // cascade — silently destroying whatever single-frame signal was
            // pending on them (a value edge, a one-shot). Only a non-recoverable
            // error is worth abandoning the rest of the pass for.
            if let executionError
            {
                if capturedError == nil { capturedError = executionError }

                // A fatal error takes precedence, so the unfinished frame is not drawn.
                if !executionError.isRecoverable
                {
                    capturedError = executionError
                    break
                }
            }
        }

        endGraphExecutionTrace(graphTraceFrame)

        if let capturedError
        {
            throw capturedError
        }
    }

    private final class GraphExecutionPlanCache
    {
        let graphID: UUID
        let graphIdentifier: ObjectIdentifier
        let connectionTopologyGeneration: Int
        private(set) var executionTopologyGeneration: Int
        private(set) var nodesInExecutionOrder: [Node]
        let planner: GraphExecutionPlanner
        // Forced extensions follow the same invariant as the root plan: pull
        // decisions only change with the graph's execution topology generation.
        private var forcedNodes: [Node]?
        private var nodesInExecutionOrderWithForcedNodes: [Node] = []

        init(graph: Graph, roots: [(node: Node, requestedOutputPort: Port?)])
        {
            graphID = graph.id
            graphIdentifier = ObjectIdentifier(graph)
            connectionTopologyGeneration = graph.connectionTopologyGeneration
            executionTopologyGeneration = graph.executionTopologyGeneration
            planner = GraphExecutionPlanner(nodes: graph.nodes)
            nodesInExecutionOrder = planner.plan(roots: roots)
        }

        func refreshPullDecisions(for graph: Graph, roots: [(node: Node, requestedOutputPort: Port?)])
        {
            executionTopologyGeneration = graph.executionTopologyGeneration
            nodesInExecutionOrder = planner.plan(roots: roots)
            forcedNodes = nil
        }

        func scheduledNodes(forcing nodesToForce: [Node]) -> [Node]
        {
            if nodesToForce.isEmpty { return nodesInExecutionOrder }

            if let forcedNodes, Self.isSameNodeList(forcedNodes, nodesToForce) {
                return nodesInExecutionOrderWithForcedNodes
            }

            forcedNodes = nodesToForce
            nodesInExecutionOrderWithForcedNodes = nodesInExecutionOrder
                + planner.plan(roots: [], alreadyScheduledNodes: nodesInExecutionOrder, forcedNodes: nodesToForce)
            return nodesInExecutionOrderWithForcedNodes
        }

        /// Iterator passes `graph.nodes` every iteration, so shared storage is the common case.
        private static func isSameNodeList(_ lhs: [Node], _ rhs: [Node]) -> Bool
        {
            guard lhs.count == rhs.count else { return false }
            let sharesStorage = lhs.withUnsafeBufferPointer { lhsBuffer in
                rhs.withUnsafeBufferPointer { $0.baseAddress == lhsBuffer.baseAddress }
            }
            return sharesStorage || zip(lhs, rhs).allSatisfy { $0 === $1 }
        }
    }

    private func executionPlan(for graph: Graph) -> GraphExecutionPlanCache
    {
        let graphIdentifier = ObjectIdentifier(graph)
        let candidate = lastExecutionPlan.flatMap { $0.graphIdentifier == graphIdentifier ? $0 : nil }
            ?? executionPlanCaches[graphIdentifier]
        if let cached = candidate,
           cached.graphID == graph.id,
           cached.connectionTopologyGeneration == graph.connectionTopologyGeneration
        {
            // Route changes invalidate pull decisions, not the nodes' identity
            // slots. Reuse storage even when a Gate changes every iteration.
            if cached.executionTopologyGeneration != graph.executionTopologyGeneration {
                cached.refreshPullDecisions(for: graph, roots: executionRoots(for: graph))
            }
            lastExecutionPlan = cached
            return cached
        }

        let plan = GraphExecutionPlanCache(graph: graph, roots: executionRoots(for: graph))
        executionPlanCaches[graphIdentifier] = plan
        lastExecutionPlan = plan
        return plan
    }

    /// Plans hold their graph's nodes strongly. A deleted subgraph node's inner
    /// graphs never execute again, so release their plans with it.
    private func forgetExecutionPlans(forSubgraphsOf node: Node)
    {
        guard let subgraphNode = node as? SubgraphNode else { return }
        let graphIdentifier = ObjectIdentifier(subgraphNode.subGraph)
        executionPlanCaches[graphIdentifier] = nil
        if lastExecutionPlan?.graphIdentifier == graphIdentifier { lastExecutionPlan = nil }
        for nestedSubgraphNode in subgraphNode.subGraph.subgraphNodes
        {
            forgetExecutionPlans(forSubgraphsOf: nestedSubgraphNode)
        }
    }

    private func executionRoots(for graph: Graph) -> [(node: Node, requestedOutputPort: Port?)]
    {
        var roots: [(node: Node, requestedOutputPort: Port?)] = graph.nodes
            .filter { $0.nodeExecutionMode == .Consumer }
            .map { ($0, nil) }

        for outputPort in graph.publishedOutputPorts()
        {
            guard let node = outputPort.node else { continue }
            roots.append((node, outputPort))
        }

        return roots
    }

    // MARK: - Execution Trace

    private func beginGraphExecutionTrace() -> GraphExecutionTraceFrameBuilder?
    {
        guard isTracingExecution else { return nil }

        let builder = GraphExecutionTraceFrameBuilder(executionIndex: traceExecutionIndex,
                                                      startedAt: CACurrentMediaTime())
        traceExecutionIndex += 1
        graphExecutionTraceStack.append(builder)
        return builder
    }

    private func endGraphExecutionTrace(_ builder: GraphExecutionTraceFrameBuilder?)
    {
        guard let builder else { return }

        if graphExecutionTraceStack.last === builder {
            graphExecutionTraceStack.removeLast()
        }
        else {
            graphExecutionTraceStack.removeAll { $0 === builder }
        }

        let execution = builder.makeExecution(endedAt: CACurrentMediaTime())

        if let nodeBuilder = nodeExecutionTraceStack.last {
            nodeBuilder.childExecutions.append(execution)
        }
        else {
            executionTrace?.executions.append(execution)
        }
    }

    private func beginNodeExecutionTrace(node: Node, orderIndex: Int) -> NodeExecutionTraceBuilder?
    {
        guard isTracingExecution,
              graphExecutionTraceStack.isEmpty == false
        else { return nil }

        let builder = NodeExecutionTraceBuilder(node: node,
                                                orderIndex: orderIndex,
                                                startedAt: CACurrentMediaTime())
        nodeExecutionTraceStack.append(builder)
        return builder
    }

    private func endNodeExecutionTrace(_ builder: NodeExecutionTraceBuilder?, result: NodeExecutionResult)
    {
        guard let builder else { return }

        if nodeExecutionTraceStack.last === builder {
            nodeExecutionTraceStack.removeLast()
        }
        else {
            nodeExecutionTraceStack.removeAll { $0 === builder }
        }

        let nodeExecution = builder.makeNodeExecution(endedAt: CACurrentMediaTime(),
                                                      result: result)
        graphExecutionTraceStack.last?.nodeExecutions.append(nodeExecution)
    }

    // MARK: - Graph Execution Lifecycle

    public func enableExecution() throws
    {
        try transitionExecution(to: .enabled)
    }

    public func startExecution(trace: Bool = false) throws
    {
        if trace {
            self.executionTrace = GraphExecutionTrace(graphID: graph.id)
            self.traceExecutionIndex = 0
            self.graphExecutionTraceStack.removeAll(keepingCapacity: true)
            self.nodeExecutionTraceStack.removeAll(keepingCapacity: true)
        }
        else {
            self.executionTrace = nil
            self.traceExecutionIndex = 0
            self.graphExecutionTraceStack.removeAll(keepingCapacity: true)
            self.nodeExecutionTraceStack.removeAll(keepingCapacity: true)
        }

        try transitionExecution(to: .started)
    }

    public func stopExecution(saveTraceTo url: URL? = nil) throws
    {
        try transitionExecution(to: .stopped)
        deferredGPUResults?.cancelAllDelivery()

        if let url {
            try saveExecutionTrace(to: url)
        }
    }

    public func saveExecutionTrace(to url: URL) throws
    {
        guard let executionTrace else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(executionTrace)
        try data.write(to: url)
        print("Saved graph execution trace: \(url.path)")
    }

    public func disableExecution() throws
    {
        try transitionExecution(to: .disabled)
        deferredGPUResults?.cancelAllDelivery()
        self.currentCamera = nil
    }

    public func teardown()
    {
        for node in graph.nodes {
            node.teardown()
        }
    }

    // MARK: - Graph Lifecycle Reconciliation

    /// Brings the nodes that edits to this renderer's graph touched to the state
    /// their connections ask for. The outermost execute of each frame calls this.
    internal func synchronizeLifecycle() throws
    {
        try reconcileTouchedNodes(in: graph, ceiling: executionState, startsAllNodes: false)
    }

    /// Moves this renderer, and every node of its graph, to `state`.
    internal func transitionExecution(to state: ExecutionState) throws
    {
        executionState = state
        try reconcileAllNodes(in: graph, ceiling: state, startsAllNodes: false)
    }

    /// Every node of `graph`, plus nodes removed since its last review.
    /// Subgraph nodes call this for their inner graph from their own lifecycle methods.
    internal func reconcileAllNodes(in graph: Graph, ceiling: ExecutionState, startsAllNodes: Bool) throws
    {
        let removedNodes = graph.takeNodesAwaitingLifecycleReview().filter { $0.graph !== graph }
        try reconcileNodes(graph.nodes + removedNodes, in: graph, ceiling: ceiling, startsAllNodes: startsAllNodes)
    }

    private func reconcileTouchedNodes(in graph: Graph, ceiling: ExecutionState, startsAllNodes: Bool) throws
    {
        try reconcileNodes(graph.takeNodesAwaitingLifecycleReview(), in: graph, ceiling: ceiling, startsAllNodes: startsAllNodes)

        // Inner graphs can be edited whether or not their subgraph node executes this frame.
        for subgraph in graph.subgraphNodes
        {
            if let childGraphRenderer = subgraph.childGraphRenderer
            {
                try childGraphRenderer.synchronizeLifecycle()
            }
            else
            {
                try reconcileTouchedNodes(in: subgraph.subGraph,
                                          ceiling: subgraph.executionState,
                                          startsAllNodes: subgraph.startsAllChildNodes)
            }
        }
    }

    /// Carries on past a node that fails: these nodes have already left the
    /// graph's review set, so stopping early would strand the rest.
    private func reconcileNodes(_ nodes: some Sequence<Node>, in graph: Graph, ceiling: ExecutionState, startsAllNodes: Bool) throws
    {
        var capturedError: (any Error)?

        for node in nodes
        {
            do
            {
                try reconcileNode(node, in: graph, ceiling: ceiling, startsAllNodes: startsAllNodes)
            }
            catch
            {
                print("Graph lifecycle: \(node): \(error)")
                if capturedError == nil { capturedError = error }
            }
        }

        if let capturedError
        {
            throw capturedError
        }
    }

    /// A node in `graph` runs while it is connected or is a consumer, limited
    /// by `ceiling`: the renderer's state, or its subgraph node's.
    private func reconcileNode(_ node: Node, in graph: Graph, ceiling: ExecutionState, startsAllNodes: Bool) throws
    {
        // A node that moved to another graph is reconciled there.
        if let owningGraph = node.graph, owningGraph !== graph { return }

        let target: ExecutionState
        if node.graph == nil
        {
            target = .disabled
            forgetExecutionPlans(forSubgraphsOf: node)
        }
        else if ceiling != .started
        {
            target = ceiling
        }
        else
        {
            // A published port connects the node through its subgraph node, or to the host.
            let isConnected = !node.inputNodes.isEmpty || !node.outputNodes.isEmpty || !node.publishedPorts().isEmpty
            target = startsAllNodes || isConnected || node.nodeExecutionMode == .Consumer ? .started : .stopped
        }

        // Leaving execution drops in-flight results even when the node's own stop or disable throws.
        if target == .stopped || target == .disabled, node.executionState != target
        {
            node.retireDeferredResults()
        }

        switch (node.executionState, target)
        {
        case (.disabled, .enabled), (.disabled, .stopped):
            try node.enableExecution(renderer: self)

        case (.disabled, .started):
            try node.enableExecution(renderer: self)
            try node.startExecution(renderer: self)

        case (.enabled, .started), (.stopped, .started):
            try node.startExecution(renderer: self)

        case (.started, .stopped):
            try node.stopExecution(renderer: self)

        case (.started, .disabled):
            // A node that fails to stop is still disabled; Graph has already removed it if it was deleted.
            do { try node.stopExecution(renderer: self) }
            catch
            {
                try? node.disableExecution(renderer: self)
                throw error
            }
            try node.disableExecution(renderer: self)

        case (.enabled, .disabled), (.stopped, .disabled):
            try node.disableExecution(renderer: self)

        default:
            // Already there, or an .enabled ceiling, which never stops a running node.
            break
        }
    }

    // MARK: - Execution Helpers

    /// Publishes a distinct image version of a reusable, resolved 2D render target. The GPU copy
    /// is encoded here, before a later invocation can overwrite the source target.
    public func newImage(copying texture: MTLTexture, commandBuffer: MTLCommandBuffer) throws -> FabricImage {
        guard texture.textureType == .type2D, texture.sampleCount == 1,
              let image = try? makeImage(width: texture.width, height: texture.height, pixelFormat: texture.pixelFormat,
                                         usage: [.shaderRead, .renderTarget], mipmapped: texture.mipmapLevelCount > 1),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw FabricError(.execution(.failed), severity: .recoverable,
                              message: "Could not copy resolved render target into a new image")
        }
        for level in 0..<texture.mipmapLevelCount {
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: level,
                      sourceOrigin: .init(x: 0, y: 0, z: 0),
                      sourceSize: .init(width: max(1, texture.width >> level),
                                        height: max(1, texture.height >> level), depth: 1),
                      to: image.texture, destinationSlice: 0, destinationLevel: level,
                      destinationOrigin: .init(x: 0, y: 0, z: 0))
        }
        blit.endEncoding()
        return image
    }

    public func newImage(withWidth width: Int, height: Int) throws -> FabricImage
    {
        return try self.newImage(withWidth: width, height: height, format: self.colorPixelFormat)
    }

    public func newImage(withWidth width: Int, height: Int, format: MTLPixelFormat) throws -> FabricImage
    {
        guard let image = try? self.makeImage(width: width, height: height, pixelFormat: format) else {
            throw FabricError(.execution(.outOfMemory),
                              severity: .recoverable,
                              message: "Could not allocate image: \(width)x\(height), \(format)")
        }
        return image
    }

    public func newImage(withWidth width: Int,
                         height: Int,
                         format: MTLPixelFormat,
                         mipmapped: Bool) throws -> FabricImage
    {
        guard mipmapped else {
            return try newImage(withWidth: width, height: height, format: format)
        }

        guard let image = try? makeImage(width: width, height: height, pixelFormat: format, mipmapped: true) else {
            throw FabricError(.execution(.outOfMemory),
                              severity: .recoverable,
                              message: "Could not allocate mipmapped image: \(width)x\(height), \(format)")
        }
        return image
    }

    public func newImage(fromPixelBuffer pixelBuffer: CVPixelBuffer) throws -> FabricImage
    {
        let image: FabricImage
        
        if let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        {
             image = try self.newImage(fromSurface: surface)
        }
        else
        {
            image = try newSharedImage(fromPixelBuffer: pixelBuffer)
        }
        
        image.textureTransform = FabricImageTextureTransform.coreVideo(pixelBuffer)
        
        return image
    }

    // MARK: - Private Image Helpers

    private func newSharedImage(fromPixelBuffer pixelBuffer: CVPixelBuffer) throws -> FabricImage
    {
        guard let format = self.metalPixelFormatForOSType(format: CVPixelBufferGetPixelFormatType(pixelBuffer))
        else {
            throw FabricError(.general(.unsupported),
                              severity: .recoverable,
                              message: "Unsupported pixel buffer format: \(CVPixelBufferGetPixelFormatType(pixelBuffer))")
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let image = try? self.makeImage(width: width, height: height, pixelFormat: format, storageMode: .shared)
        else {
            throw FabricError(.execution(.outOfMemory),
                              severity: .recoverable,
                              message: "Could not allocate shared image from pixel buffer: \(width)x\(height), \(format)")
        }

        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw FabricError(.execution(.failed),
                              severity: .recoverable,
                              message: "Could not read pixel buffer base address")
        }

        let region = MTLRegionMake3D(0, 0, 0, width, height, 1)
        image.texture.replace(region: region, mipmapLevel: 0, withBytes: baseAddr, bytesPerRow: bpr)
        
        
        return image
    }

    private func newImage(fromSurface surface: IOSurface) throws -> FabricImage
    {
        let descriptor = self.metalTextureDescriptorForIOSurface(surface: surface)

        if let descriptor,
           let texture = self.device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0)
        {
            IOSurfaceIncrementUseCount(surface)
            return FabricImage.managed(texture: texture) { _ in
                IOSurfaceDecrementUseCount(surface)
            }
        }

        throw FabricError(.execution(.outOfMemory),
                          severity: .recoverable,
                          message: "Could not allocate image from IOSurface")
    }

    private func metalTextureDescriptorForIOSurface(surface: IOSurfaceRef) -> MTLTextureDescriptor?
    {
        let width  = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        let format = IOSurfaceGetPixelFormat(surface)
        guard let metalFormat = self.metalPixelFormatForOSType(format: format) else { return nil }
        return self.textureDescriptor(width: width, height: height, format: metalFormat)
    }

    private func metalPixelFormatForOSType(format: OSType) -> MTLPixelFormat?
    {
        switch format {
        // 8-bit packed RGBA
        case kCVPixelFormatType_32BGRA:         return .bgra8Unorm
        case kCVPixelFormatType_32RGBA:         return .rgba8Unorm

        // 10-bit HDR
        case kCVPixelFormatType_ARGB2101010LEPacked: return .bgr10a2Unorm

        // 16-bit half-float
        case kCVPixelFormatType_64RGBAHalf:     return .rgba16Float

        // 32-bit float
        case kCVPixelFormatType_128RGBAFloat:   return .rgba32Float

        // Single-component
        case kCVPixelFormatType_OneComponent8:       return .r8Unorm
        case kCVPixelFormatType_OneComponent16Half:  return .r16Float
        case kCVPixelFormatType_OneComponent32Float: return .r32Float

        // Two-component (e.g. optical flow: X in R, Y in G)
        case kCVPixelFormatType_TwoComponent8:       return .rg8Unorm
        case kCVPixelFormatType_TwoComponent16Half:  return .rg16Float
        case kCVPixelFormatType_TwoComponent32Float: return .rg32Float

        default:
            return nil
        }
    }

    private func textureDescriptor(width: Int, height: Int, format: MTLPixelFormat) -> MTLTextureDescriptor
    {
        let desc = MTLTextureDescriptor()
        desc.width = width
        desc.height = height
        desc.pixelFormat = format
        desc.textureType = .type2D
        desc.mipmapLevelCount = 1
        desc.sampleCount = 1
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        return desc
    }

    /// Every image version is a new texture from the context's allocator, shared by every renderer
    /// handed that context. Its memory returns to the heap when the image's last owner (a port,
    /// material, recording or command buffer) lets go; textures are never reissued.
    internal func makeImage(width: Int,
                            height: Int,
                            pixelFormat: MTLPixelFormat,
                            storageMode: MTLStorageMode = .private,
                            usage: MTLTextureUsage = [.shaderRead, .shaderWrite, .renderTarget],
                            mipmapped: Bool = false,
                            label: String? = nil) throws -> FabricImage
    {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: mipmapped)
        descriptor.usage = usage
        descriptor.storageMode = storageMode
        return FabricImage.unmanaged(texture: try context.gpuAllocator.makeTexture(descriptor, label: label))
    }
}
