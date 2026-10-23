import Foundation
import Metal

/// Pool recycling stays suspended until CPU execution ends and every submitted segment completes.
/// Dropping an unsubmitted segment's completion token counts as abandonment, without a GPU wait.
final class GraphTextureRecyclingScope {
    private let lock = NSLock()
    private var pendingSegments = 0
    private var ended = false
    private var finished = false
    private let onFinish: (GraphTextureRecyclingScope) -> Void
    // Accessed only under the retirement domain's lock.
    var retirements: [GraphTextureRetirement] = []

    init(onFinish: @escaping (GraphTextureRecyclingScope) -> Void) {
        self.onFinish = onFinish
    }

    func makeCompletion() -> Completion {
        lock.lock()
        precondition(!ended, "Register GPU segments before ending texture recycling collection")
        pendingSegments += 1
        lock.unlock()
        return Completion(scope: self)
    }

    func retain(untilCompleted commandBuffer: MTLCommandBuffer) {
        let completion = makeCompletion()
        commandBuffer.addCompletedHandler { _ in completion.complete() }
    }

    func end() { update(ending: true) }

    private func update(ending: Bool) {
        lock.lock()
        if ending { ended = true }
        else { pendingSegments -= 1 }
        let shouldFinish = ended && pendingSegments == 0 && !finished
        if shouldFinish { finished = true }
        lock.unlock()
        if shouldFinish { onFinish(self) }
    }

    final class Completion {
        private let lock = NSLock()
        private var scope: GraphTextureRecyclingScope?
        fileprivate init(scope: GraphTextureRecyclingScope) { self.scope = scope }
        func complete() {
            lock.lock()
            let scope = self.scope
            self.scope = nil
            lock.unlock()
            scope?.update(ending: false)
        }
        deinit { complete() }
    }
}

/// Shared by overlapping scopes. Only the last scope returns this texture to the pool.
final class GraphTextureRetirement {
    private let recycle: () -> Void
    init(recycle: @escaping () -> Void) { self.recycle = recycle }
    deinit { recycle() }
}

/// Fabric images can cross renderer and pool boundaries. A shared retirement domain protects
/// those transfers without discovering images on ports. Independent pending executions retain
/// conservatively; no pool makes a retired texture available until all those scopes finish.
final class GraphTextureRecycling: @unchecked Sendable {
    static let shared = GraphTextureRecycling()
    private let lock = NSLock()
    private var pendingExecutions: [GraphTextureRecyclingScope] = []

    func beginExecution() -> GraphTextureRecyclingScope {
        lock.lock()
        defer { lock.unlock() }
        let scope = GraphTextureRecyclingScope { [weak self] in self?.finishExecution($0) }
        pendingExecutions.append(scope)
        return scope
    }

    func retire(recycle: @escaping () -> Void) {
        lock.lock()
        guard !pendingExecutions.isEmpty else {
            lock.unlock()
            recycle()
            return
        }
        let retirement = GraphTextureRetirement(recycle: recycle)
        for scope in pendingExecutions { scope.retirements.append(retirement) }
        lock.unlock()
    }

    private func finishExecution(_ scope: GraphTextureRecyclingScope) {
        lock.lock()
        pendingExecutions.removeAll { $0 === scope }
        let retirements = scope.retirements
        scope.retirements = []
        lock.unlock()
        // Recycling takes a pool lock. Release ownership outside the domain lock.
        withExtendedLifetime(retirements) {}
    }
}
