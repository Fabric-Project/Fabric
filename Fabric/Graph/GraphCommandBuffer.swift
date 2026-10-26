import Metal
import MetalPerformanceShaders
import Foundation

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

    /// After this GPU segment completes, perform asynchronous work on independent inputs.
    /// Only `receive` runs on the graph execution owner, with the original node/Iterator scope.
    /// The operation must not access nodes or ports; capture invocation-owned data instead.
    public func addCompletion<Value>(operation: @escaping () async throws -> Value,
                                     receive: @escaping (Value) throws -> Void) throws {
        guard let commands = self as? GraphCommandBuffer else {
            throw GraphCompletionError.requiresGraphCommandBuffer
        }
        try commands.registerAsyncCompletion(operation: operation, receive: receive)
    }
}

/// Typed result slots are reused with their admitted frame segment; ordinary Metal completions
/// never allocate these. Only result transfer crosses threads, not node or port state.
class GraphDeferredAsyncResultSlot {
    func clear() {}
}

final class GraphAsyncCompletionResult<Value>: GraphDeferredAsyncResultSlot {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func store(_ result: Result<Value, Error>) { lock.withLock { self.result = result } }
    override func clear() { lock.withLock { result = nil } }

    func take() throws -> Value {
        let result = lock.withLock {
            defer { self.result = nil }
            return self.result
        }
        guard let result else { preconditionFailure("Asynchronous completion delivered before its result") }
        return try result.get()
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

    fileprivate func registerAsyncCompletion<Value>(operation: @escaping () async throws -> Value,
                                                     receive: @escaping (Value) throws -> Void) throws {
        guard let graphRenderer, executingNode != nil else { throw GraphCompletionError.requiresNodeExecution }
        guard !recordingEnded, rootCommandBuffer.status.rawValue < MTLCommandBufferStatus.committed.rawValue
        else { throw GraphCompletionError.commandBufferAlreadySubmitted }
        if deferredBatch == nil { deferredBatch = graphRenderer.ensureDeferredResults().admit() }
        let segment = currentDeferredSegment()
        let result: GraphAsyncCompletionResult<Value> = segment.asyncResult()
        try registerCompletion { try receive(result.take()) }
        segment.appendAsyncOperation {
            do { result.store(.success(try await operation())) }
            catch { result.store(.failure(error)) }
        }
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
