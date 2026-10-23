import Testing
import Metal
import Foundation
@testable import Fabric

@Suite("Texture recycling scopes", .serialized)
struct TextureRecyclingScopeTests {
    private func makeCache(recycling: GraphTextureRecycling = GraphTextureRecycling()) throws -> GraphRendererTextureCache {
        let device = try #require(MTLCreateSystemDefaultDevice())
        var configuration = GraphRendererTextureCache.Configuration()
        configuration.framePoolCount = 1
        configuration.minimumHeapSizeBytes = 1024 * 1024
        return GraphRendererTextureCache(device: device, config: configuration, recycling: recycling)
    }

    private func image(_ cache: GraphRendererTextureCache) throws -> FabricImage {
        try #require(cache.newManagedImage(width: 4, height: 4, pixelFormat: .rgba8Unorm))
    }

    @Test("An existing image released during execution cannot be reused before scope end")
    func existingImageIsDeferred() throws {
        let cache = try makeCache()
        var original: FabricImage? = try image(cache)
        let texture = try #require(original).texture
        let scope = cache.beginExecution()
        original = nil
        let other = try image(cache)
        #expect(other.texture !== texture)
        scope.end()
        let reused = try image(cache)
        #expect(reused.texture === texture)
    }

    @Test("Releases after CPU execution wait for pending GPU completion")
    func lateReleaseWaitsForCompletion() throws {
        let cache = try makeCache()
        var original: FabricImage? = try image(cache)
        let texture = try #require(original).texture
        let scope = cache.beginExecution()
        let completion = scope.makeCompletion()
        scope.end()
        original = nil
        let other = try image(cache)
        #expect(other.texture !== texture)
        completion.complete()
        let reused = try image(cache)
        #expect(reused.texture === texture)
    }

    @Test("Overlapping scopes must both finish before storage can be reused")
    func overlappingScopes() throws {
        let cache = try makeCache()
        var original: FabricImage? = try image(cache)
        let texture = try #require(original).texture
        let outer = cache.beginExecution()
        let inner = cache.beginExecution()
        original = nil
        inner.end()
        let other = try image(cache)
        #expect(other.texture !== texture)
        outer.end()
        #expect(try image(cache).texture === texture)
    }

    @Test("A submitted earlier segment stays protected when the tail is abandoned")
    func abandonedTailPreservesSubmittedSegment() throws {
        let cache = try makeCache()
        var original: FabricImage? = try image(cache)
        let texture = try #require(original).texture
        let scope = cache.beginExecution()
        let submitted = scope.makeCompletion()
        var abandoned = scope.makeCompletion() as GraphTextureRecyclingScope.Completion?
        original = nil
        scope.end()
        abandoned = nil
        #expect(abandoned == nil)
        let other = try image(cache)
        #expect(other.texture !== texture)
        submitted.complete()
        #expect(try image(cache).texture === texture)
    }

    @Test("Virtual nested collections need no discovery or image registration")
    func nestedCollectionRelease() throws {
        let cache = try makeCache()
        let port = NodePort<PortValue>(name: "Images", kind: .Outlet)
        var original: FabricImage? = try image(cache)
        let texture = try #require(original).texture
        port.value = .Dictionary(["history": .Array([.Image(try #require(original))])])
        original = nil
        let scope = cache.beginExecution()
        let completion = scope.makeCompletion()
        port.value = nil
        scope.end()
        let other = try image(cache)
        #expect(other.texture !== texture)
        completion.complete()
        #expect(try image(cache).texture === texture)
    }

    @Test("A scope protects cached images originating from another renderer pool")
    func crossPoolRelease() throws {
        let recycling = GraphTextureRecycling()
        let producer = try makeCache(recycling: recycling)
        let consumer = try makeCache(recycling: recycling)
        var original: FabricImage? = try image(producer)
        let texture = try #require(original).texture
        let scope = consumer.beginExecution()
        let completion = scope.makeCompletion()
        original = nil
        scope.end()
        let other = try image(producer)
        #expect(other.texture !== texture)
        completion.complete()
        #expect(try image(producer).texture === texture)
    }

    @Test("The command buffer shares a nested scope and releases it after real GPU completion")
    func commandBufferScopeCompletes() throws {
        let cache = try makeCache(recycling: .shared)
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let raw = try #require(queue.makeCommandBuffer())
        let commands = GraphCommandBuffer(commandBuffer: raw)
        let scope = try #require(commands.beginTextureRecycling())
        #expect(commands.beginTextureRecycling() == nil)
        var original: FabricImage? = try image(cache)
        let texture = try #require(original).texture
        original = nil
        commands.endTextureRecycling(scope)
        let other = try image(cache)
        #expect(other.texture !== texture)
        commands.commit()
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)
        #expect(try image(cache).texture === texture)
    }

    @Test("A real submitted segment survives abandonment of its uncommitted continuation")
    func commandBufferAbandonedContinuation() throws {
        let cache = try makeCache(recycling: .shared)
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let raw = try #require(queue.makeCommandBuffer())
        let event = try #require(device.makeSharedEvent())
        defer { event.signaledValue = 1 }
        raw.encodeWaitForEvent(event, value: 1)
        var original: FabricImage? = try image(cache)
        let texture = try #require(original).texture
        try autoreleasepool {
            let commands = GraphCommandBuffer(commandBuffer: raw)
            let scope = try #require(commands.beginTextureRecycling())
            original = nil
            commands.commitAndContinue()
            commands.endTextureRecycling(scope)
        }
        let other = try image(cache)
        #expect(other.texture !== texture)
        event.signaledValue = 1
        raw.waitUntilCompleted()
        #expect(raw.status == .completed)
        #expect(try image(cache).texture === texture)
    }

    @Test("No execution scope means ordinary immediate recycling")
    func ordinaryRecycling() throws {
        let cache = try makeCache()
        var original: FabricImage? = try image(cache)
        let texture = try #require(original).texture
        original = nil
        #expect(try image(cache).texture === texture)
    }
}
