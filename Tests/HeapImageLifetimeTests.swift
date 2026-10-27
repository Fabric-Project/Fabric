import Testing
import Foundation
import Metal
import Satin
@testable import Fabric

@Suite("Heap-backed image lifetime", .serialized)
struct HeapImageLifetimeTests {
    private func makeAllocator() throws -> GPUAllocator {
        let device = try #require(MTLCreateSystemDefaultDevice())
        var configuration = GPUAllocator.Configuration()
        configuration.heapGrowthSize = 1024 * 1024
        return GPUAllocator(device: device, configuration: configuration)
    }

    /// A CPU-readable image, so tests can fill and read it back.
    private func image(_ allocator: GPUAllocator) throws -> FabricImage {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .shared
        return FabricImage.unmanaged(texture: try allocator.makeTexture(descriptor))
    }

    private func fill(_ texture: MTLTexture, byte: UInt8) {
        let bytes = [UInt8](repeating: byte, count: texture.width * texture.height * 4)
        bytes.withUnsafeBytes { storage in
            if let address = storage.baseAddress {
                texture.replace(region: MTLRegionMake2D(0, 0, texture.width, texture.height),
                                mipmapLevel: 0, withBytes: address, bytesPerRow: texture.width * 4)
            }
        }
    }

    private func pixels(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { storage in
            if let address = storage.baseAddress {
                texture.getBytes(address, bytesPerRow: texture.width * 4,
                                 from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            }
        }
        return bytes
    }

    @Test("A retained texture cannot be reissued when its image wrapper disappears")
    func retainedTextureCannotBeOverwritten() throws {
        let allocator = try makeAllocator()
        var original: FabricImage? = try image(allocator)
        let texture = try #require(original).texture
        fill(texture, byte: 17)
        original = nil
        let replacement = try image(allocator)
        fill(replacement.texture, byte: 233)
        #expect(replacement.texture !== texture)
        #expect(pixels(texture).allSatisfy { $0 == 17 })
    }

    @Test("Heap allocation is reusable after every texture owner releases it")
    func lastOwnerReleasesHeapAllocation() throws {
        let allocator = try makeAllocator()
        var observedHeap: MTLHeap?
        try autoreleasepool {
            let original = try image(allocator)
            observedHeap = original.texture.heap
            #expect(try #require(observedHeap).usedSize > 0)
        }
        #expect(try #require(observedHeap).usedSize == 0)
    }
    @Test("An input port keeps its image storage alive without renderer bookkeeping")
    func inputPortOwnsImage() throws {
        let allocator = try makeAllocator()
        let input = NodePort<FabricImage>(name: "Image", kind: .Inlet)
        var heap: MTLHeap?
        weak var witness: FabricImage?
        try autoreleasepool {
            let original = try image(allocator)
            heap = original.texture.heap
            witness = original
            input.value = original
        }
        #expect(witness != nil)
        #expect(try #require(heap).usedSize > 0)
        autoreleasepool { input.value = nil }
        #expect(witness == nil)
        #expect(try #require(heap).usedSize == 0)
    }

    @Test("Nested virtual collections own their images without discovery or registration")
    func nestedCollectionOwnsImage() throws {
        let allocator = try makeAllocator()
        let port = NodePort<PortValue>(name: "Images", kind: .Outlet)
        var heap: MTLHeap?
        try autoreleasepool {
            let original = try image(allocator)
            heap = original.texture.heap
            port.value = .Dictionary(["history": .Array([.Image(original)])])
        }
        #expect(try #require(heap).usedSize > 0)
        autoreleasepool { port.value = nil }
        #expect(try #require(heap).usedSize == 0)
    }

    @Test("A material owns texture storage independently of its image wrapper")
    func materialOwnsTexture() throws {
        let allocator = try makeAllocator()
        let device = try #require(MTLCreateSystemDefaultDevice())
        let material = BasicTextureMaterial(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm))
        var heap: MTLHeap?
        weak var witness: FabricImage?
        try autoreleasepool {
            let original = try image(allocator)
            heap = original.texture.heap
            witness = original
            material.texture = original.texture
        }
        #expect(witness == nil)
        #expect(try #require(heap).usedSize > 0)
        let other = try image(allocator)
        fill(other.texture, byte: 233)
        #expect(other.texture !== material.texture)
        autoreleasepool { material.texture = nil }
        // The replacement remains live; clearing the material must release only its allocation.
        #expect(try #require(heap).usedSize == other.texture.allocatedSize)
    }

    @Test("Trimming the allocator does not invalidate texture owners")
    func trimPreservesLiveTexture() throws {
        let allocator = try makeAllocator()
        let original = try image(allocator)
        fill(original.texture, byte: 17)
        let heap = try #require(original.texture.heap)
        allocator.trim()
        let other = try image(allocator)
        fill(other.texture, byte: 233)
        #expect(original.texture.heap === heap)
        #expect(other.texture !== original.texture)
        #expect(pixels(original.texture).allSatisfy { $0 == 17 })
    }

    @Test("A pending raw or graph command buffer keeps a released image's texture readable", arguments: [false, true])
    func GPUOwnsTexture(wrapped: Bool) throws {
        let allocator = try makeAllocator()
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let raw = try #require(queue.makeCommandBuffer())
        let commands: MTLCommandBuffer = wrapped ? GraphCommandBuffer(commandBuffer: raw) : raw
        let event = try #require(device.makeSharedEvent())
        defer { event.signaledValue = 1 }
        commands.encodeWaitForEvent(event, value: 1)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        descriptor.storageMode = .shared
        let destination = try #require(device.makeTexture(descriptor: descriptor))
        weak var witness: FabricImage?
        try autoreleasepool {
            let original = try image(allocator)
            witness = original
            fill(original.texture, byte: 17)
            let blit = try #require(commands.makeBlitCommandEncoder())
            blit.copy(from: original.texture, to: destination)
            blit.endEncoding()
        }
        #expect(witness == nil)
        let replacement = try image(allocator)
        fill(replacement.texture, byte: 233)
        commands.commit()
        #expect(commands.status != .completed)
        event.signaledValue = 1
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)
        #expect(pixels(destination).allSatisfy { $0 == 17 })
    }

    @Test("An abandoned continuation cannot invalidate an earlier submitted texture use")
    func abandonedContinuationPreservesSubmittedTexture() throws {
        let allocator = try makeAllocator()
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let submitted = try #require(queue.makeCommandBuffer())
        let event = try #require(device.makeSharedEvent())
        defer { event.signaledValue = 1 }
        submitted.encodeWaitForEvent(event, value: 1)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        descriptor.storageMode = .shared
        let destination = try #require(device.makeTexture(descriptor: descriptor))
        try autoreleasepool {
            let commands = GraphCommandBuffer(commandBuffer: submitted)
            let original = try image(allocator)
            fill(original.texture, byte: 17)
            let blit = try #require(commands.makeBlitCommandEncoder())
            blit.copy(from: original.texture, to: destination)
            blit.endEncoding()
            commands.commitAndContinue()
        }
        let replacement = try image(allocator)
        fill(replacement.texture, byte: 233)
        event.signaledValue = 1
        submitted.waitUntilCompleted()
        #expect(submitted.status == .completed)
        #expect(pixels(destination).allSatisfy { $0 == 17 })
    }
    private final class ImportedImageConsumer: Node {
        override class var name: String { "Imported Image Consumer" }
        override class var nodeType: Node.NodeType { .Utility }
        override class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
        override class var nodeTimeMode: Node.TimeMode { .None }
        override class var nodeDescription: String { "Copies and relinquishes an imported image" }
        var source: FabricImage?
        var destination: MTLTexture?

        override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo,
                              renderPassDescriptor: MTLRenderPassDescriptor,
                              commandBuffer: MTLCommandBuffer) throws {
            guard let source, let destination else { return }
            let blit = try #require(commandBuffer.makeBlitCommandEncoder())
            blit.copy(from: source.texture, to: destination)
            blit.endEncoding()
            self.source = nil
        }
    }

    @Test("A consuming renderer preserves an imported texture after its image is released", arguments: [false, true])
    func importedImageSurvivesGPUUse(wrapped: Bool) throws {
        let harness = try #require(GraphExecutionTestHarness(renderWidth: 4, renderHeight: 4))
        let producer = harness.renderer
        var original: FabricImage? = try producer.makeImage(width: 4, height: 4, pixelFormat: .rgba8Unorm, storageMode: .shared)
        weak var imageWitness = original
        let pixel: [UInt8] = [25, 50, 75, 255]
        let expected = Array(repeating: pixel, count: 16).flatMap { $0 }
        let sourceIdentity = try autoreleasepool {
            let texture = try #require(original).texture
            expected.withUnsafeBytes { bytes in
                if let address = bytes.baseAddress {
                    texture.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0,
                                    withBytes: address, bytesPerRow: 16)
                }
            }
            return ObjectIdentifier(texture)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        descriptor.storageMode = .shared
        let destination = try #require(harness.context.device.makeTexture(descriptor: descriptor))
        let graph = Graph(context: harness.context)
        let node = ImportedImageConsumer(context: harness.context)
        node.source = original
        node.destination = destination
        original = nil
        graph.addNode(node)
        let consumer = harness.graphRenderer(for: graph)
        try consumer.startExecution()
        defer { try? consumer.stopExecution() }
        let commands = try #require(wrapped ? consumer.makeCommandBuffer() : consumer.commandQueue.makeCommandBuffer())
        let event = try #require(harness.context.device.makeSharedEvent())
        defer { event.signaledValue = 1 }
        commands.encodeWaitForEvent(event, value: 1)
        try consumer.execute(graph: graph, executionInfo: harness.makeExecutionInfo(),
                             renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commands)
        #expect(node.source == nil)
        #expect(imageWitness == nil)
        let other = try producer.makeImage(width: 4, height: 4, pixelFormat: .rgba8Unorm, storageMode: .shared)
        fill(other.texture, byte: 233)
        #expect(ObjectIdentifier(other.texture) != sourceIdentity,
                "The producer cannot reuse storage still read by the consumer")
        commands.commit()
        event.signaledValue = 1
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)
        var actual = [UInt8](repeating: 0, count: expected.count)
        actual.withUnsafeMutableBytes { bytes in
            if let address = bytes.baseAddress {
                destination.getBytes(address, bytesPerRow: 16,
                                     from: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0)
            }
        }
        #expect(actual.elementsEqual(expected))
    }

    @Test("An unrelated pending renderer cannot hold this allocator's released storage")
    func unrelatedRendererDoesNotHoldStorage() throws {
        let harness = try #require(GraphExecutionTestHarness(renderWidth: 4, renderHeight: 4))
        let renderer = harness.renderer
        try renderer.startExecution()
        defer { try? renderer.stopExecution() }
        let commands = try #require(renderer.makeCommandBuffer())
        let event = try #require(harness.context.device.makeSharedEvent())
        defer { event.signaledValue = 1 }
        commands.encodeWaitForEvent(event, value: 1)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = try harness.makeTexture()
        try renderer.executeAndDraw(executionInfo: harness.makeExecutionInfo(), renderPassDescriptor: pass,
                                    commandBuffer: commands)
        commands.commit()
        let allocator = try makeAllocator()
        var heap: MTLHeap?
        try autoreleasepool {
            let unused = try image(allocator)
            heap = unused.texture.heap
        }
        #expect(commands.status != .completed)
        #expect(try #require(heap).usedSize == 0)
        event.signaledValue = 1
        commands.waitUntilCompleted()
        #expect(commands.status == .completed)
    }

}
