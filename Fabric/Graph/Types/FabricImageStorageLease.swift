import Foundation
import Metal

/// Pool ownership is independent of Metal object retention. A texture can stay alive while its
/// bytes are incorrectly reused; this lease prevents reuse until its image and GPU uses end.
final class FabricImageStorageLease {
    let texture: MTLTexture
    private let lock = NSLock()
    private var hasLogicalOwner = true
    private var gpuUseCount = 0
    private var onRelease: ((MTLTexture) -> Void)?

    init(texture: MTLTexture, onRelease: ((MTLTexture) -> Void)?) {
        self.texture = texture
        self.onRelease = onRelease
    }

    func acquireGPUUse() -> GPUUse {
        lock.lock()
        gpuUseCount += 1
        lock.unlock()
        return GPUUse(lease: self)
    }

    func releaseLogicalOwner() {
        release(logicalOwner: true)
    }

    private func release(logicalOwner: Bool) {
        lock.lock()
        if logicalOwner { hasLogicalOwner = false }
        else { gpuUseCount -= 1 }
        let callback = !hasLogicalOwner && gpuUseCount == 0 ? onRelease : nil
        if callback != nil { onRelease = nil }
        lock.unlock()
        // Pool callbacks may take their own lock. Never invoke them under the lease lock.
        callback?(texture)
    }

    final class GPUUse {
        private let lease: FabricImageStorageLease
        fileprivate init(lease: FabricImageStorageLease) { self.lease = lease }
        deinit { lease.release(logicalOwner: false) }
    }
}

/// One graph invocation's image uses. The completion handler keeps these uses through the final
/// segment; releasing an uncommitted command buffer also releases the handler and its uses.
final class GraphFrameImageUses {
    private var uses: [FabricImageStorageLease.GPUUse] = []

    func retain(_ image: FabricImage) {
        retain(image.storageLease)
    }

    func retain(_ lease: FabricImageStorageLease) {
        uses.append(lease.acquireGPUUse())
    }

    func retainImages(in ports: [Port]) {
        for port in ports {
            if let image = (port as? NodePort<FabricImage>)?.value {
                retain(image)
            } else if containsImages(port.portType), let value = port.snapshotValue() {
                retainImages(in: value)
            }
        }
    }

    private func containsImages(_ type: PortType) -> Bool {
        switch type {
        case .Image, .Virtual: return true
        case let .Array(element), let .Dictionary(element): return containsImages(element)
        default: return false
        }
    }

    private func retainImages(in value: PortValue) {
        switch value {
        case let .Image(image): retain(image)
        case let .Array(values): for value in values { retainImages(in: value) }
        case let .Dictionary(values): for value in values.values { retainImages(in: value) }
        default: break
        }
    }

    func retain(untilCompleted commandBuffer: MTLCommandBuffer) {
        let batch = CompletionBatch(uses: uses)
        commandBuffer.addCompletedHandler { _ in batch.complete() }
    }

    private final class CompletionBatch {
        private var uses: [FabricImageStorageLease.GPUUse]
        init(uses: [FabricImageStorageLease.GPUUse]) { self.uses = uses }
        func complete() { uses.removeAll() }
    }
}
