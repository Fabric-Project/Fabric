import Foundation
import Metal

/// When an analyzer makes a GPU-produced CPU value available to downstream nodes.
public enum GPUResultDeliveryMode: String, CaseIterable, Codable {
    case sync = "Sync" // Same execution
    case async = "Async" // Future execution after command buffer completes
}

/// A per-node result handoff. GPU completion only marks an immutable readback ready; decoding and
/// publishing happen on the execution owner. Each request must capture its own output storage.
/// A next-frame result is the latest completed request, available in a later frame; no GPU wait
/// occurs. Slow GPU work can take more than one frame. This object never mutates node ports.
public final class GPUResultReadback<Value> {
    private struct Request: Equatable {
        let generation: UInt64
        let sequence: UInt64
        let frameNumber: Int
    }
    private final class PendingRequest {
        let owner: GPUResultReadback<Value>
        let request: Request
        var completed = false
        init(owner: GPUResultReadback<Value>, request: Request) {
            self.owner = owner
            self.request = request
        }
        deinit {
            if !completed { owner.abandon(request) }
        }
    }
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var sequence: UInt64 = 0
    private var pendingCount = 0
    private var retryRequired = false
    private var lastCompletedSequence: UInt64 = 0
    private var completed: (request: Request, reader: Result<() throws -> Value, Error>)?

    public init() {}

    /// Keep a processor eligible for execution until its result is consumed. Completion never
    /// reaches into the node to mark it dirty, and a clean static input still delivers its result.
    public var hasPendingResult: Bool { lock.withLock { pendingCount > 0 || completed != nil || retryRequired } }

    /// The last request was discarded before submission; re-encode it on the execution owner.
    public var needsRetry: Bool { lock.withLock { retryRequired } }

    private func abandon(_ request: Request) {
        lock.withLock {
            if request.generation == generation {
                pendingCount -= 1
                if request.sequence == sequence { retryRequired = true }
            }
        }
    }

    /// Cancel result delivery, including callbacks still pending on the GPU. Their resources remain
    /// retained by their command buffers. Call when inputs disappear, mode changes, or execution stops.
    public func reset() {
        lock.withLock {
            generation &+= 1
            completed = nil
            pendingCount = 0
            retryRequired = false
        }
    }

    /// Read a result made ready in an earlier frame. Invoke on the node's execution owner, even
    /// when no input changed, so a static image can deliver a deferred result exactly once.
    public func takeCompleted(beforeFrame frameNumber: Int) throws -> Value? {
        let reader: Result<() throws -> Value, Error>? = lock.withLock {
            guard let ready = completed, ready.request.frameNumber < frameNumber else { return nil }
            completed = nil
            return ready.reader
        }
        guard let reader else { return nil }
        return try reader.get()()
    }

    /// All encoders must be ended and managed-storage synchronization encoded before this call.
    /// The reader runs only on the execution owner, after successful GPU completion. It must capture
    /// request values/resources, never consult mutable node inputs or shared output buffers.
    public func read(renderer: GraphRenderer, commandBuffer: MTLCommandBuffer,
                     mode: GPUResultDeliveryMode, frameNumber: Int,
                     reader: @escaping () throws -> Value) throws -> Value? {
        if mode == .sync {
            reset()
            try renderer.waitForGPUResults(commandBuffer: commandBuffer)
            return try reader()
        }
        let request = lock.withLock {
            sequence &+= 1
            pendingCount += 1
            retryRequired = false
            return Request(generation: generation, sequence: sequence, frameNumber: frameNumber)
        }
        let pending = PendingRequest(owner: self, request: request)
        commandBuffer.addCompletedHandler { [self, pending] buffer in
            // Metal may invoke handlers while destroying a buffer that was never committed.
            // That is abandonment, not a GPU failure or a result ready for publication.
            guard buffer.status == .completed || buffer.status == .error else { return }
            pending.completed = true
            let result: Result<() throws -> Value, Error> = buffer.status == .completed
                ? .success(reader) : .failure(GraphReadbackError.commandBufferFailed(buffer.error))
            lock.withLock {
                guard request.generation == generation else { return }
                pendingCount -= 1
                guard request.sequence > lastCompletedSequence else { return }
                lastCompletedSequence = request.sequence
                completed = (request, result)
            }
        }
        return nil
    }
}
