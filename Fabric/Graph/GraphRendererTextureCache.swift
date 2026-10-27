//
//  GraphRendererTextureCache.swift
//  Fabric
//
//  Created by Anton Marini on 12/24/25.
//

import Foundation
import Metal

/// Renderer-local heap storage. Every image version gets its own texture object; normal texture
/// ownership (ports, materials, recordings and Metal command buffers) keeps its allocation live.
/// Automatic heaps reuse memory only after the last resource owner releases it.
internal final class GraphRendererTextureCache {

    // MARK: Configuration

    public struct Configuration: Sendable
    {
        public var storageMode: MTLStorageMode = .private
        public var cpuCacheMode: MTLCPUCacheMode = .defaultCache
        public var heapType: MTLHeapType = .automatic

        /// When we need a new heap, allocate at least this many bytes (helps avoid tiny heaps).
        public var minimumHeapSizeBytes: Int = 1024 * 1024 * 1024 // 1GB

        /// Growth factor when sizing a heap for a new texture request.
        /// New heap size = max(minimumHeapSize, textureSize * growthFactor)
        public var heapGrowthFactor: Int = 2

        /// Alignment floor used when aligning heap sizes.
        public var heapSizeAlignment: Int = 256

        /// Maximum number of heaps retained by the cache. Live textures can keep an evicted
        /// heap alive independently until their own CPU/GPU owners release them.
        public var maxHeapCount: Int = 16

        public init() {}
    }

    // MARK: State

    private let device: MTLDevice
    private let stateLock = NSLock()
    public let config: Configuration

    private var heaps: [MTLHeap] = []

    // Optional stats/debug
    public private(set) var totalHeapsCreated: Int = 0
    public private(set) var totalTexturesAllocated: Int = 0
    public private(set) var totalAllocationMisses: Int = 0
    public private(set) var totalResets: Int = 0
    public private(set) var totalHeapsEvicted: Int = 0

    // MARK: Init

    init(device: MTLDevice, config: Configuration = .init()) {
        self.device = device
        self.config = config
    }

    // MARK: Public API: vend images

    /// Allocate a distinct texture from reusable heap storage. Releasing the image never
    /// reissues its texture: material, recording or GPU owners can still be using that resource.
    public func newManagedImage(width: Int,
                                height: Int,
                                pixelFormat: MTLPixelFormat,
                                usage: MTLTextureUsage = [.shaderRead, .shaderWrite, .renderTarget],
                                mipmapped: Bool = false,
                                label: String? = nil) -> FabricImage? {

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                            width: width,
                                                            height: height,
                                                            mipmapped: mipmapped)
        desc.textureType = .type2D
        desc.usage = usage
        desc.storageMode = config.storageMode
        desc.cpuCacheMode = config.cpuCacheMode

        guard let texture = makeTexture(descriptor: desc, label: label) else { return nil }

        return FabricImage.unmanaged(texture: texture)
    }

    /// Wrap an externally created texture (assets, static defaults, imported resources).
    /// This does not allocate new heap storage.
    public func newUnmanagedImage(from texture: MTLTexture) -> FabricImage {
        FabricImage.unmanaged(texture: texture)
    }

    // MARK: Optional: explicit flush / maintenance

    /// Drop cached heaps. Existing textures keep their own backing storage alive.
    public func reset() {
        stateLock.lock()
        defer { stateLock.unlock() }
        heaps.removeAll(keepingCapacity: false)
        totalResets += 1
    }

    // MARK: Internals: allocate heap storage

    private func makeTexture(descriptor: MTLTextureDescriptor, label: String?) -> MTLTexture? {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let texture = allocateFromExistingHeaps(descriptor: descriptor, label: label) {
            totalTexturesAllocated += 1
            return texture
        }

        totalAllocationMisses += 1
        if let texture = allocateFromNewHeap(descriptor: descriptor, label: label) {
            totalTexturesAllocated += 1
            return texture
        }
        return nil
    }

    private func allocateFromExistingHeaps(descriptor: MTLTextureDescriptor, label: String?) -> MTLTexture?
    {
        // A bounded first-fit scan; texture ownership determines available heap storage.
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
        heapDesc.hazardTrackingMode = .tracked

        guard let heap = device.makeHeap(descriptor: heapDesc) else { return nil }
        totalHeapsCreated += 1
        heap.label = "Fabric.TextureHeap.\(totalHeapsCreated)"

        heaps.append(heap)
        enforceHeapCountLimit()

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

    private func enforceHeapCountLimit()
    {
        let limit = max(1, config.maxHeapCount)
        guard heaps.count > limit else { return }

        let overflow = heaps.count - limit
        heaps.removeFirst(overflow)
        totalHeapsEvicted += overflow
    }
}
