import Metal
import MetalPerformanceShaders

public enum GraphCompletionError: Error {
    case requiresGraphCommandBuffer
    case requiresNodeExecution
    case commandBufferAlreadySubmitted
}

extension MTLCommandBuffer {
    /// Decode and stage this node's outputs after GPU completion, on the graph execution owner.
    /// Captures must own independent readback storage. Existing output.send calls publish at the
    /// next execution of the matching node/Iterator context, never on Metal's callback thread.
    public func addCompletion(_ body: @escaping () throws -> Void) throws {
        guard let commands = self as? GraphCommandBuffer else {
            throw GraphCompletionError.requiresGraphCommandBuffer
        }
        try commands.registerCompletion(body)
    }
}

/// One recycling scope for nested graph execution on this buffer. Every submitted segment
/// participates, including continuations made by MPS and an abandoned final segment.
final class GraphCommandBuffer: MPSCommandBuffer {
    var graphRenderer: GraphRenderer?
    var executingNode: Node?
    var executingIterator: IteratorNode?
    var deferredBatch: GraphDeferredFrameBatch?
    private var deferredSegment: GraphDeferredSegment?
    private var recordingEnded = false
    private var recyclingScope: GraphTextureRecyclingScope?

    func beginTextureRecycling() -> GraphTextureRecyclingScope? {
        guard recyclingScope == nil else { return nil }
        let scope = GraphTextureRecycling.shared.beginExecution()
        recyclingScope = scope
        return scope
    }

    func endTextureRecycling(_ scope: GraphTextureRecyclingScope) {
        scope.retain(untilCompleted: self)
        scope.end()
        recyclingScope = nil
    }

    override func commitAndContinue() {
        if deferredBatch != nil { currentDeferredSegment().markSubmitted() }
        recyclingScope?.retain(untilCompleted: rootCommandBuffer)
        super.commitAndContinue()
        deferredSegment = nil
    }

    override func commit() {
        if let deferredBatch {
            currentDeferredSegment().markSubmitted()
            deferredBatch.finishRecording()
        }
        recordingEnded = true
        super.commit()
    }

    private func currentDeferredSegment() -> GraphDeferredSegment {
        if let deferredSegment { return deferredSegment }
        guard let deferredBatch else { preconditionFailure("A deferred segment requires its admitted frame") }
        let segment = deferredBatch.appendSegment()
        let generation = segment.generation
        rootCommandBuffer.addCompletedHandler { buffer in
            switch buffer.status {
            case .completed: segment.complete(.completed, generation: generation)
            case .error: segment.complete(.failed(buffer.error), generation: generation)
            default: segment.complete(.abandoned, generation: generation)
            }
        }
        deferredSegment = segment
        return segment
    }

    func resultScope() -> GraphDeferredResultScope {
        if let executingIterator { return executingIterator.deferredResultScope(commands: self) }
        guard let graphRenderer else { preconditionFailure("Deferred results require a graph owner") }
        return graphRenderer.ensureDeferredResults().defaultScope
    }

    fileprivate func registerCompletion(_ body: @escaping () throws -> Void) throws {
        guard let graphRenderer, let executingNode else { throw GraphCompletionError.requiresNodeExecution }
        guard !recordingEnded, rootCommandBuffer.status.rawValue < MTLCommandBufferStatus.committed.rawValue
        else { throw GraphCompletionError.commandBufferAlreadySubmitted }
        if deferredBatch == nil { deferredBatch = graphRenderer.ensureDeferredResults().admit() }
        let binding: GraphDeferredNodeBinding
        if let existing = executingNode.deferredResultsBinding { binding = existing }
        else {
            binding = GraphDeferredNodeBinding(outputs: executingNode.outputPorts())
            executingNode.deferredResultsBinding = binding
        }
        let scope = resultScope()
        currentDeferredSegment().requests.append(.init(binding: binding, scope: scope,
            state: scope.state(for: binding), generation: binding.generation, body: body))
    }

    deinit {
        if !recordingEnded {
            if rootCommandBuffer.status.rawValue >= MTLCommandBufferStatus.committed.rawValue {
                deferredSegment?.markSubmitted()
            }
            deferredSegment?.abandonIfUnsubmitted()
            deferredBatch?.finishRecording()
        }
    }
}
