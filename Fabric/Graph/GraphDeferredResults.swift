import Foundation

/// Only async-participating outputs receive this cell. It never owns its node or ports.
final class GraphDeferredSendCapture {
    var state: GraphDeferredNodeState?
    var binding: GraphDeferredNodeBinding?
    var generation: UInt64 = 0

    func stage<Value>(_ value: Value?, port: NodePort<Value>, index: Int, force: Bool) -> Bool {
        guard let state, let binding else { return false }
        guard generation == binding.generation else { return true }
        state.stage(value, port: port, index: index, force: force)
        return true
    }
}

final class GraphDeferredNodeBinding {
    private(set) var outputs: [Port]
    let captureCell = GraphDeferredSendCapture()
    private(set) var generation: UInt64 = 0
    private(set) var retired = false
    var participating: [Bool]
    var participatingIndices: [Int] = []
    private var states: [GraphDeferredNodeState] = []
    private var scopeHandles: [(domain: GraphDeferredScopeDomain, index: Int)] = []

    fileprivate func handle(in domain: GraphDeferredScopeDomain) -> Int {
        // Usually one execution owner. Handles are assigned only on first use in a root.
        if let existing = scopeHandles.first, existing.domain === domain { return existing.index }
        if let existing = scopeHandles.dropFirst().first(where: { $0.domain === domain }) { return existing.index }
        let index = domain.allocateNodeHandle()
        scopeHandles.append((domain, index))
        return index
    }

    init(outputs: [Port]) {
        self.outputs = outputs
        participating = Array(repeating: false, count: outputs.count)
        for index in outputs.indices {
            outputs[index].deferredSendCapture = captureCell
            outputs[index].deferredOutputIndex = index
        }
    }

    func invalidate() {
        generation &+= 1
        for state in states { state.reset(generation: generation) }
    }

    func retire() {
        invalidate()
        retired = true
        for output in outputs where output.deferredSendCapture === captureCell {
            output.deferredSendCapture = nil
        }
        outputs.removeAll()
        states.removeAll()
    }

    func makeState() -> GraphDeferredNodeState {
        states.removeAll { !$0.valid }
        let state = GraphDeferredNodeState(generation: generation)
        states.append(state)
        return state
    }

    func capture(in state: GraphDeferredNodeState, body: () throws -> Void) throws {
        state.prepare(generation: generation, outputCount: outputs.count)
        captureCell.state = state
        captureCell.binding = self
        let capturedGeneration = generation
        captureCell.generation = generation
        defer {
            captureCell.state = nil
            captureCell.binding = nil
        }
        do {
            try body()
            if generation == capturedGeneration { state.commit(binding: self) }
            else { state.discard() }
        } catch {
            state.discard()
            throw error
        }
    }
}

private class GraphDeferredOutputSlot {
    var touched = false
    func commit() {}
    func discard() {}
    func publish() {}
}

private final class GraphDeferredTypedSlot<Value: PortValueRepresentable>: GraphDeferredOutputSlot {
    let port: NodePort<Value>
    var staged: Value?
    var stored: Value?
    var stagedForce = false
    var storedForce = false
    init(port: NodePort<Value>) { self.port = port }
    override func commit() {
        guard touched else { return }
        stored = staged
        storedForce = stagedForce
        discard()
    }
    override func discard() {
        staged = nil
        stagedForce = false
        touched = false
    }
    override func publish() {
        port.send(stored, force: storedForce)
        storedForce = false
    }
}

final class GraphDeferredNodeState {
    private(set) var valid = true
    private var generation: UInt64
    private var slots: [GraphDeferredOutputSlot?] = []
    private var touchedIndices: [Int] = []
    private(set) var hasPreparedDelivery = false
    private(set) var slotCreationCount = 0

    init(generation: UInt64) { self.generation = generation }

    func reset(generation: UInt64) {
        slots.removeAll(keepingCapacity: true)
        touchedIndices.removeAll(keepingCapacity: true)
        hasPreparedDelivery = false
        self.generation = generation
    }

    func invalidate() {
        valid = false
        reset(generation: generation)
    }

    func prepare(generation: UInt64, outputCount: Int) {
        if self.generation != generation {
            reset(generation: generation)
        }
        if slots.count < outputCount {
            slots.append(contentsOf: repeatElement(nil, count: outputCount - slots.count))
        }
    }

    func stage<Value>(_ value: Value?, port: NodePort<Value>, index: Int, force: Bool) {
        let slot: GraphDeferredTypedSlot<Value>
        if let existing = slots[index] as? GraphDeferredTypedSlot<Value> {
            slot = existing
        } else {
            slot = GraphDeferredTypedSlot(port: port)
            slots[index] = slot
            slotCreationCount += 1
        }
        if !slot.touched { touchedIndices.append(index) }
        slot.staged = value
        slot.stagedForce = force
        slot.touched = true
    }

    func commit(binding: GraphDeferredNodeBinding) {
        for index in touchedIndices {
            slots[index]?.commit()
            if !binding.participating[index] {
                binding.participating[index] = true
                binding.participatingIndices.append(index)
            }
        }
        touchedIndices.removeAll(keepingCapacity: true)
        hasPreparedDelivery = true
    }
    func discard() {
        for index in touchedIndices { slots[index]?.discard() }
        touchedIndices.removeAll(keepingCapacity: true)
    }

    func publish(binding: GraphDeferredNodeBinding) {
        prepare(generation: binding.generation, outputCount: binding.outputs.count)
        for index in binding.participatingIndices {
            if let slot = slots[index] { slot.publish() }
            else { binding.outputs[index].sendBoxed(nil) }
        }
        hasPreparedDelivery = false
    }
}

/// Shared by a root and all its iteration scopes; contains no node references.
fileprivate final class GraphDeferredScopeDomain {
    private var nextNodeHandle = 0
    func allocateNodeHandle() -> Int {
        defer { nextNodeHandle += 1 }
        return nextNodeHandle
    }
}

/// Scopes own typed states, never nodes. Only async registrations create them.
final class GraphDeferredResultScope {
    private(set) var valid = true
    private struct Entry {
        let binding: GraphDeferredNodeBinding
        let state: GraphDeferredNodeState
    }
    private var states: [Entry?] = []
    fileprivate let domain: GraphDeferredScopeDomain

    init() { domain = GraphDeferredScopeDomain() }

    fileprivate init(domain: GraphDeferredScopeDomain) {
        self.domain = domain
    }

    fileprivate var iteratorBranches: [GraphDeferredIteratorBranch?] = []
    private var nextIteratorHandle = 0

    fileprivate func allocateIteratorHandle() -> Int {
        defer { nextIteratorHandle += 1 }
        return nextIteratorHandle
    }

    func state(for binding: GraphDeferredNodeBinding) -> GraphDeferredNodeState {
        let index = binding.handle(in: domain)
        if index < states.count, let entry = states[index] { return entry.state }
        // Cold insertion also drops retired bindings without shifting stable handles.
        for existingIndex in states.indices where states[existingIndex]?.binding.retired == true {
            states[existingIndex] = nil
        }
        if states.count <= index {
            states.append(contentsOf: repeatElement(nil, count: index + 1 - states.count))
        }
        let state = binding.makeState()
        states[index] = Entry(binding: binding, state: state)
        return state
    }

    func invalidate() {
        valid = false
        for entry in states { entry?.state.invalidate() }
        states.removeAll()
        for branch in iteratorBranches { branch?.invalidate() }
        iteratorBranches.removeAll()
    }
}

final class GraphDeferredIteratorBranch {
    var valid = true
    var scopes: [GraphDeferredResultScope?] = []
    func invalidate() {
        valid = false
        for scope in scopes { scope?.invalidate() }
        scopes.removeAll()
    }
    func resize(_ count: Int) {
        if scopes.count > count {
            for scope in scopes[count...] { scope?.invalidate() }
            scopes.removeSubrange(count...)
        }
        if scopes.count < count {
            scopes.append(contentsOf: repeatElement(nil, count: count - scopes.count))
        }
    }
}

/// Each Iterator owns its branches; its root-local handle indexes every enclosing scope directly.
/// There is no global ID counter, identity map, path reconstruction or per-execution hashing.
final class GraphDeferredIteratorScopes {
    let root: GraphDeferredResultScope
    private let handle: Int
    private var ownedBranches: [GraphDeferredIteratorBranch] = []

    init(root: GraphDeferredResultScope) {
        self.root = root
        handle = root.allocateIteratorHandle()
    }

    @discardableResult
    func prepare(parent: GraphDeferredResultScope, count: Int) -> GraphDeferredIteratorBranch {
        if parent.iteratorBranches.count <= handle {
            parent.iteratorBranches.append(contentsOf: repeatElement(nil, count: handle + 1 - parent.iteratorBranches.count))
        }
        let branch: GraphDeferredIteratorBranch
        if let existing = parent.iteratorBranches[handle], existing.valid { branch = existing }
        else {
            ownedBranches.removeAll { !$0.valid }
            branch = GraphDeferredIteratorBranch()
            parent.iteratorBranches[handle] = branch
            ownedBranches.append(branch)
        }
        branch.resize(count)
        return branch
    }

    func scope(parent: GraphDeferredResultScope, index: Int, count: Int) -> GraphDeferredResultScope {
        let branch = prepare(parent: parent, count: count)
        if let scope = branch.scopes[index], scope.valid { return scope }
        let scope = GraphDeferredResultScope(domain: parent.domain)
        branch.scopes[index] = scope
        return scope
    }

    func invalidate() {
        for branch in ownedBranches { branch.invalidate() }
        ownedBranches.removeAll()
    }
}

/// The only cross-thread state in deferred delivery. Readiness notifications cannot be lost
/// between owner-side draining and a frame-admission wait.
final class GraphDeferredSignal {
    let condition = NSCondition()
    private var revision: UInt64 = 0
    func snapshot() -> UInt64 { condition.withLock { revision } }
    func notifyLocked() { revision &+= 1; condition.broadcast() }
    func wait(after observed: UInt64) {
        condition.lock()
        while revision == observed { condition.wait() }
        condition.unlock()
    }
}

final class GraphDeferredSegment {
    struct Request {
        let binding: GraphDeferredNodeBinding
        let scope: GraphDeferredResultScope
        let state: GraphDeferredNodeState
        let generation: UInt64
        var body: (() throws -> Void)?
    }
    enum Status { case pending, completed, failed(Error?), abandoned }
    let signal: GraphDeferredSignal
    private(set) var generation: UInt64 = 0
    private var status: Status = .pending
    private(set) var submitted = false
    var requests: [Request] = []
    var processed = false
    private var asyncOperations: [() async -> Void] = []
    private var outstandingAsyncOperations = 0
    private var asyncResults: [GraphDeferredAsyncResultSlot] = []
    private var asyncResultCount = 0

    init(signal: GraphDeferredSignal) { self.signal = signal }
    func reset() {
        signal.condition.lock()
        generation &+= 1
        status = .pending
        submitted = false
        outstandingAsyncOperations = 0
        signal.condition.unlock()
        asyncOperations.removeAll(keepingCapacity: true)
        clearAsyncResults()
        requests.removeAll(keepingCapacity: true)
        processed = false
    }
    func markSubmitted() { submitted = true }
    func appendAsyncOperation(_ operation: @escaping () async -> Void) {
        asyncOperations.append(operation)
    }
    func asyncResult<Value>() -> GraphAsyncCompletionResult<Value> {
        let index = asyncResultCount
        asyncResultCount += 1
        if index < asyncResults.count {
            if let result = asyncResults[index] as? GraphAsyncCompletionResult<Value> { return result }
            let result = GraphAsyncCompletionResult<Value>()
            asyncResults[index] = result
            return result
        }
        let result = GraphAsyncCompletionResult<Value>()
        asyncResults.append(result)
        return result
    }
    func clearAsyncResults() {
        for index in 0..<asyncResultCount { asyncResults[index].clear() }
        asyncResultCount = 0
    }
    func complete(_ status: Status, generation: UInt64) {
        signal.condition.lock()
        guard self.generation == generation else {
            signal.condition.unlock()
            return
        }
        if asyncOperations.isEmpty {
            self.status = status
            signal.notifyLocked()
            signal.condition.unlock()
            return
        }
        // Keep readiness pending until every task is launched and the closure array is cleared.
        // This lets us reuse that array without copying it, or racing owner-side segment reuse.
        self.status = .pending
        if case .completed = status { outstandingAsyncOperations = asyncOperations.count }
        signal.condition.unlock()
        // Start only after successful GPU completion, outside the condition lock. No node state
        // is touched here; the existing owner-side drain performs every output publication.
        if case .completed = status {
            for operation in asyncOperations {
                Task {
                    await operation()
                    self.finishAsyncOperation(generation: generation)
                }
            }
        }
        asyncOperations.removeAll(keepingCapacity: true)
        signal.condition.lock()
        self.status = status
        signal.notifyLocked()
        signal.condition.unlock()
    }
    private func finishAsyncOperation(generation: UInt64) {
        signal.condition.lock()
        if self.generation == generation {
            outstandingAsyncOperations -= 1
            signal.notifyLocked()
        }
        signal.condition.unlock()
    }
    func abandonIfUnsubmitted() {
        if !submitted { complete(.abandoned, generation: generation) }
    }
    var completionStatus: Status {
        signal.condition.withLock {
            if case .completed = status, outstandingAsyncOperations > 0 { return .pending }
            return status
        }
    }
}

final class GraphDeferredFrameBatch {
    let signal: GraphDeferredSignal
    var order: UInt64 = 0
    var inUse = false
    var recordingEnded = false
    private var segments: [GraphDeferredSegment] = []
    private var segmentCount = 0

    init(signal: GraphDeferredSignal) { self.signal = signal }
    func begin(order: UInt64) {
        self.order = order
        inUse = true
        recordingEnded = false
        segmentCount = 0
    }
    func appendSegment() -> GraphDeferredSegment {
        let segment: GraphDeferredSegment
        if segmentCount < segments.count { segment = segments[segmentCount] }
        else {
            segment = GraphDeferredSegment(signal: signal)
            segments.append(segment)
        }
        segmentCount += 1
        segment.reset()
        return segment
    }
    func process(errors: inout [Error]) {
        for index in 0..<segmentCount {
            let segment = segments[index]
            if segment.processed { continue }
            switch segment.completionStatus {
            case .pending: return // Preserve submission order within this frame.
            case .completed:
                for requestIndex in segment.requests.indices {
                    let request = segment.requests[requestIndex]
                    if request.scope.valid, request.binding.generation == request.generation,
                       let body = request.body {
                        do { try request.binding.capture(in: request.state, body: body) }
                        catch { errors.append(error) }
                    }
                    segment.requests[requestIndex].body = nil
                }
            case let .failed(error): errors.append(GraphReadbackError.commandBufferFailed(error))
            case .abandoned: break
            }
            segment.requests.removeAll(keepingCapacity: true)
            segment.clearAsyncResults()
            segment.processed = true
        }
        if recordingEnded { inUse = false }
    }
    func finishRecording() {
        recordingEnded = true
        signal.condition.lock()
        signal.notifyLocked()
        signal.condition.unlock()
    }
}

/// Lazily created on the first completion registration. All mutation except segment readiness
/// stays on the execution owner. Batches retain capacity and are reused at the admission limit.
final class GraphDeferredResults {
    private(set) var defaultScope = GraphDeferredResultScope()
    private let signal = GraphDeferredSignal()
    private let limit: Int
    private var batches: [GraphDeferredFrameBatch] = []
    private var order: UInt64 = 0
    private var errors: [Error] = []
    private(set) var batchCreationCount = 0

    init(limit: Int) { self.limit = max(1, limit) }

    func processReady() {
        // At most the configured in-flight count; no UUID lookups, sorting or copied work lists.
        var after: UInt64 = 0
        for _ in batches.indices {
            var next: GraphDeferredFrameBatch?
            for batch in batches where batch.inUse && batch.order > after {
                if let selected = next {
                    if batch.order < selected.order { next = batch }
                } else { next = batch }
            }
            guard let next else { break }
            next.process(errors: &errors)
            after = next.order
            // Do not let later frames' results overtake a still-pending earlier frame.
            if next.inUse { break }
        }
    }

    func admit() -> GraphDeferredFrameBatch {
        while true {
            let revision = signal.snapshot()
            processReady()
            if let batch = batches.first(where: { !$0.inUse }) {
                order &+= 1
                batch.begin(order: order)
                return batch
            }
            if batches.count < limit {
                let batch = GraphDeferredFrameBatch(signal: signal)
                batches.append(batch)
                batchCreationCount += 1
                order &+= 1
                batch.begin(order: order)
                return batch
            }
            signal.wait(after: revision)
        }
    }

    func cancelAllDelivery() {
        defaultScope.invalidate()
        defaultScope = GraphDeferredResultScope()
        processReady()
    }

    func takeErrors() -> [Error] {
        guard !errors.isEmpty else { return [] }
        let result = errors
        errors.removeAll(keepingCapacity: true)
        return result
    }
}
