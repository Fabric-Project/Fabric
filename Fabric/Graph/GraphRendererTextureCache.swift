//
//  GraphRendererTextureCache.swift
//  Fabric
//
//  Created by Anton Marini on 12/24/25.
//

import Foundation
import Metal

// MARK: - TextureHeapCache
//
// A standalone manager that allocates textures from one or more MTLHeaps and
// reuses them via a per-frame ring pool.
//
// - Allocations come from heap.makeTexture(descriptor:)
// - "Deallocation" is implemented as recycling into a pool keyed by a descriptor signature.
// - Safety: recycled textures go into the *current* frame pool, and are only reused when
//   that pool comes around again (ring-buffered), avoiding most in-flight reuse hazards.
//
// Designed to vend FabricImage using the new API:
//
//   FabricImage.managed(texture:onRelease:)  // internal factory
//   FabricImage.unmanaged(texture:)         // public factory
//   image.release()                         // optional explicit return; also called in deinit
//

internal final class GraphRendererTextureCache {

    // MARK: Configuration

    public struct Configuration: Sendable
    {
        public var storageMode: MTLStorageMode = .private
        public var cpuCacheMode: MTLCPUCacheMode = .defaultCache
        public var heapType: MTLHeapType = .automatic

        /// Number of frame pools in the reuse ring. (Triple buffering default.)
        public var framePoolCount: Int = 3

        /// When we need a new heap, allocate at least this many bytes (helps avoid tiny heaps).
        public var minimumHeapSizeBytes: Int = 128 * 1024 * 1024 // 128 MB

        /// Growth factor when sizing a heap for a new texture request.
        /// New heap size = max(minimumHeapSize, textureSize * growthFactor)
        public var heapGrowthFactor: Int = 2

        /// Alignment floor used when aligning heap sizes.
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

    /// Call once per renderer frame (or per graph evaluation tick).
    /// Use a monotonically increasing frameNumber (e.g. timing.frameNumber).
    public func resetCacheFor(executionContext:GraphExecutionContext)
    {
        let frameNumber = executionContext.timing.frameNumber
        let count = max(1, config.framePoolCount)
        self.frameIndex = ((frameNumber % count) + count) % count
    }

    // MARK: Public API: vend images

    /// Create a managed FabricImage allocated from heaps + cache.
    /// The returned FabricImage will automatically recycle its texture when released/deinitialized,
    /// assuming FabricImage calls its `onRelease` callback.
    ///
    /// You can customize usage as needed. Default is suitable for "render + compute" intermediate images.
    public func newManagedImage(width: Int,
                                height: Int,
                                pixelFormat: MTLPixelFormat,
                                usage: MTLTextureUsage = [.shaderRead, .shaderWrite, .renderTarget],
                                mipmapped: Bool = false,
                                label: String? = nil) -> FabricImage? {

        var desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                            width: width,
                                                            height: height,
                                                            mipmapped: mipmapped)
        desc.textureType = .type2D
        desc.usage = usage
        desc.storageMode = config.storageMode
        desc.cpuCacheMode = config.cpuCacheMode

        guard let texture = makeTexture(descriptor: desc, label: label) else { return nil }

        // IMPORTANT: avoid a retain cycle.
        // The FabricImage retains the onRelease closure; the closure should not strongly retain self.
        return FabricImage.managed(texture: texture) { [weak self] tex in
            self?.recycleTexture(tex)
        }
    }

    /// Wrap an externally created texture (assets, static defaults, imported resources).
    /// This does NOT participate in heap allocation or recycling.
    public func newUnmanagedImage(from texture: MTLTexture) -> FabricImage {
        FabricImage.unmanaged(texture: texture)
    }

    // MARK: Optional: explicit flush / maintenance

    /// Drops all cached reusable textures (does NOT destroy heaps immediately, but releases references).
    /// Useful for memory pressure events or when changing output resolution dramatically.
    public func flushReusableTextures() {
        for i in available.indices {
            available[i].removeAll(keepingCapacity: false)
        }
    }

    /// Drops all heaps and cached textures. Next allocation will recreate heaps.
    /// Use sparingly (it forces reallocations).
    public func reset() {
        flushReusableTextures()
        heaps.removeAll(keepingCapacity: false)
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

        // 1) Reuse from pool
        if var bucket = available[frameIndex][key], let tex = bucket.popLast() {
            available[frameIndex][key] = bucket
            totalTexturesReused += 1
            if let label { tex.label = label }
            return tex
        }

        // 2) Allocate from existing heap(s)
        if let tex = allocateFromExistingHeaps(descriptor: descriptor, label: label) {
            totalTexturesAllocated += 1
            return tex
        }

        // 3) Grow: create a new heap sized for this texture (plus headroom)
        if let tex = allocateFromNewHeap(descriptor: descriptor, label: label) {
            totalTexturesAllocated += 1
            return tex
        }

        return nil
    }

    private func recycleTexture(_ texture: MTLTexture)
    {
        // Only recycle textures that match our storage mode.
        // (A stronger check is possible, but this is a good first line of defense.)
        guard texture.storageMode == config.storageMode else { return }

        let key = TextureKey(width: texture.width,
                             height: texture.height,
                             pixelFormat: texture.pixelFormat,
                             mipmapLevelCount: texture.mipmapLevelCount,
                             sampleCount: texture.sampleCount,
                             textureType: texture.textureType,
                             usageRawValue: texture.usage.rawValue,
                             storageMode: texture.storageMode)

        available[frameIndex][key, default: []].append(texture)
    }

    private func allocateFromExistingHeaps(descriptor: MTLTextureDescriptor, label: String?) -> MTLTexture?
    {
        // Simple first-fit scan. If you want to optimize, track heap free space heuristics.
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

        // Align heap size up to max(texAlign, heapSizeAlignment)
        let alignment = max(texAlign, config.heapSizeAlignment)
        let heapSize = alignUp(desired, to: alignment)

        let heapDesc = MTLHeapDescriptor()
        heapDesc.size = heapSize
        heapDesc.storageMode = config.storageMode
        heapDesc.cpuCacheMode = config.cpuCacheMode
        heapDesc.type = config.heapType

        guard let heap = device.makeHeap(descriptor: heapDesc) else { return nil }
        totalHeapsCreated += 1
        heap.label = "Fabric.TextureHeap.\(totalHeapsCreated)"

        heaps.append(heap)

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
