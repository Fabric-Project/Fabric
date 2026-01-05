//
//  GraphRendererTextureCache.swift
//  Fabric
//
//  Created by Anton Marini on 12/24/25.
//

import Foundation
import Metal

internal final class GraphRendererTextureCache {

    // MARK: Configuration

    public struct Configuration: Sendable
    {
        public var storageMode: MTLStorageMode = .private
        public var cpuCacheMode: MTLCPUCacheMode = .defaultCache
        public var heapType: MTLHeapType = .automatic
        public var framePoolCount: Int = 3
        public var minimumHeapSizeBytes: Int = 128 * 1024 * 1024 // 128 MB
        public var heapGrowthFactor: Int = 2
        public var heapSizeAlignment: Int = 256
        public init() {}
    }

    // MARK: Types

    private struct TextureKey: Hashable
    {
        let width: Int
        let height: Int
        let pixelFormat: MTLPixelFormat
        let mipmapLevelCount: Int
        let sampleCount: Int
        let textureType: MTLTextureType
        let usageRawValue: UInt
        let storageMode: MTLStorageMode
    }

    private let lock = NSLock()

    private struct PendingItem {
        let frameIndex: Int
        let key: TextureKey
        let texture: MTLTexture
    }

    // Textures released (CPU) but not yet eligible for reuse until CB completes
    private var pendingTexturesByCommandBufferID: [ObjectIdentifier: [PendingItem]] = [:]

    // Ensures we install exactly one completion handler per command buffer
    private var completionHandlerInstalledForCommandBufferIDs: Set<ObjectIdentifier> = []

    // MARK: State

    private let device: MTLDevice
    public let config: Configuration

    private var heaps: [MTLHeap] = []
    private var available: [[TextureKey: [MTLTexture]]] = []
    private var frameIndex: Int = 0

    // Optional stats/debug
    public private(set) var totalHeapsCreated: Int = 0
    public private(set) var totalTexturesReused: Int = 0
    public private(set) var totalTexturesAllocated: Int = 0

    // MARK: Init

    public init(device: MTLDevice, config: Configuration = .init()) {
        self.device = device
        self.config = config
        self.available = Array(repeating: [:], count: max(1, config.framePoolCount))
    }

    // MARK: Frame lifecycle

    public func resetCacheFor(executionContext: GraphExecutionContext)
    {
        let frameNumber = executionContext.timing.frameNumber
        let count = max(1, config.framePoolCount)
        let newIndex = ((frameNumber % count) + count) % count

        lock.lock()
        self.frameIndex = newIndex
        lock.unlock()
    }

    // MARK: Public API: vend images

    public func newManagedImage(width: Int,
                                height: Int,
                                pixelFormat: MTLPixelFormat,
                                commandBuffer: MTLCommandBuffer,
                                usage: MTLTextureUsage = [.shaderRead, .shaderWrite, .renderTarget],
                                mipmapped: Bool = false,
                                label: String? = nil) -> FabricImage? {

        // MUST be installed before commit; do it here so recycle never needs to.
        registerCompletionHandlerIfNeeded(commandBuffer: commandBuffer)

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                            width: width,
                                                            height: height,
                                                            mipmapped: mipmapped)
        desc.textureType = .type2D
        desc.usage = usage
        desc.storageMode = config.storageMode
        desc.cpuCacheMode = config.cpuCacheMode

        guard let texture = makeTexture(descriptor: desc, label: label) else { return nil }

        let key = TextureKey(width: texture.width,
                             height: texture.height,
                             pixelFormat: texture.pixelFormat,
                             mipmapLevelCount: texture.mipmapLevelCount,
                             sampleCount: texture.sampleCount,
                             textureType: texture.textureType,
                             usageRawValue: texture.usage.rawValue,
                             storageMode: texture.storageMode)

        return FabricImage.managed(texture: texture, commandBuffer: commandBuffer) { [weak self] tex, cb in
            self?.enqueueRecycle(tex, key: key, commandBuffer: cb)
        }
    }

    public func newUnmanagedImage(from texture: MTLTexture) -> FabricImage {
        FabricImage.unmanaged(texture: texture)
    }

    // MARK: Optional: explicit flush / maintenance

    public func flushReusableTextures() {
        lock.lock()
        for i in available.indices {
            available[i].removeAll(keepingCapacity: false)
        }
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        for i in available.indices {
            available[i].removeAll(keepingCapacity: false)
        }
        heaps.removeAll(keepingCapacity: false)
        pendingTexturesByCommandBufferID.removeAll(keepingCapacity: false)
        completionHandlerInstalledForCommandBufferIDs.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    // MARK: Internals: completion handler install (safe)

    private func registerCompletionHandlerIfNeeded(commandBuffer: MTLCommandBuffer) {
        let cbID = ObjectIdentifier(commandBuffer)

        lock.lock()
        let needsInstall = completionHandlerInstalledForCommandBufferIDs.insert(cbID).inserted
        lock.unlock()

        guard needsInstall else { return }

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.drainPendingRecycles(for: cbID)
        }
    }

    private func drainPendingRecycles(for commandBufferID: ObjectIdentifier) {
        let items: [PendingItem]

        lock.lock()
        items = pendingTexturesByCommandBufferID.removeValue(forKey: commandBufferID) ?? []
        completionHandlerInstalledForCommandBufferIDs.remove(commandBufferID)
        lock.unlock()

        guard !items.isEmpty else { return }

        lock.lock()
        for item in items {
            let safeIndex = (item.frameIndex + 1) % self.available.count
            available[safeIndex][item.key, default: []].append(item.texture)
        }
        lock.unlock()
    }

    // MARK: Internals: allocate/reuse

    private func makeTexture(descriptor: MTLTextureDescriptor, label: String?) -> MTLTexture? {
        let key = TextureKey(width: descriptor.width,
                             height: descriptor.height,
                             pixelFormat: descriptor.pixelFormat,
                             mipmapLevelCount: descriptor.mipmapLevelCount,
                             sampleCount: descriptor.sampleCount,
                             textureType: descriptor.textureType,
                             usageRawValue: descriptor.usage.rawValue,
                             storageMode: descriptor.storageMode)

        // 1) Reuse from pool (LOCKED: fixes crash)
        lock.lock()
        if var bucket = available[frameIndex][key], let tex = bucket.popLast() {
            available[frameIndex][key] = bucket
            totalTexturesReused += 1
            lock.unlock()

            if let label { tex.label = label }
            return tex
        }
        lock.unlock()

        // 2) Allocate from existing heap(s)
        if let tex = allocateFromExistingHeaps(descriptor: descriptor, label: label) {
            lock.lock()
            totalTexturesAllocated += 1
            lock.unlock()
            return tex
        }

        // 3) Grow: create a new heap sized for this texture (plus headroom)
        if let tex = allocateFromNewHeap(descriptor: descriptor, label: label) {
            lock.lock()
            totalTexturesAllocated += 1
            lock.unlock()
            return tex
        }

        return nil
    }

    // Enqueue recycle; completion handler will move into `available`.
    // IMPORTANT: does NOT add handlers (avoid “released after commit” hazard).
    private func enqueueRecycle(_ texture: MTLTexture,
                                key: TextureKey,
                                commandBuffer: MTLCommandBuffer) {
        guard texture.storageMode == config.storageMode else { return }

        let cbID = ObjectIdentifier(commandBuffer)

        // Capture the frame pool index at time of release
        lock.lock()
        let capturedFrameIndex = self.frameIndex
        pendingTexturesByCommandBufferID[cbID, default: []].append(
            PendingItem(frameIndex: capturedFrameIndex, key: key, texture: texture)
        )
        lock.unlock()
    }

    private func allocateFromExistingHeaps(descriptor: MTLTextureDescriptor, label: String?) -> MTLTexture?
    {
        // NOTE: Metal heap allocation itself is thread-safe, but we keep heaps array stable.
        // If you ever mutate `heaps` concurrently, wrap the iteration in `lock` too.
        for heap in heaps
        {
            if let tex = heap.makeTexture(descriptor: descriptor)
            {
                if let label { tex.label = label }
                return tex
            }
        }
        return nil
    }

    private func allocateFromNewHeap(descriptor: MTLTextureDescriptor, label: String?) -> MTLTexture?
    {
        let sizeAndAlign = device.heapTextureSizeAndAlign(descriptor: descriptor)
        let texBytes = Int(sizeAndAlign.size)
        let texAlign = Int(sizeAndAlign.align)

        guard texBytes > 0 else { return nil }

        let growth = max(1, config.heapGrowthFactor)
        let desired = max(config.minimumHeapSizeBytes, texBytes * growth)

        let alignment = max(texAlign, config.heapSizeAlignment)
        let heapSize = alignUp(desired, to: alignment)

        let heapDesc = MTLHeapDescriptor()
        heapDesc.size = heapSize
        heapDesc.storageMode = config.storageMode
        heapDesc.cpuCacheMode = config.cpuCacheMode
        heapDesc.type = config.heapType
        heapDesc.hazardTrackingMode = .tracked

        guard let heap = device.makeHeap(descriptor: heapDesc) else { return nil }

        lock.lock()
        totalHeapsCreated += 1
        heap.label = "Fabric.TextureHeap.\(totalHeapsCreated)"
        heaps.append(heap)
        lock.unlock()

        let tex = heap.makeTexture(descriptor: descriptor)
        if let label { tex?.label = label }
        return tex
    }

    private func alignUp(_ value: Int, to alignment: Int) -> Int
    {
        let a = max(1, alignment)
        let mask = a - 1
        return (value + mask) & ~mask
    }
}

