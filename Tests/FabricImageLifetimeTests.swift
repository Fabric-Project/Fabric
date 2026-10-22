import Testing
import Metal
@testable import Fabric

@Suite("Fabric image storage lifetime")
struct FabricImageLifetimeTests {
    private func texture() throws -> MTLTexture {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        return try #require(device.makeTexture(descriptor: descriptor))
    }

    @Test("Logical release waits for every outstanding GPU use")
    func releaseWaitsForEveryUse() throws {
        var returns = 0
        var image: FabricImage? = .managed(texture: try texture()) { _ in returns += 1 }
        var firstUse = image?.storageLease.acquireGPUUse()
        var secondUse = image?.storageLease.acquireGPUUse()
        #expect(firstUse != nil && secondUse != nil)
        image = nil
        #expect(returns == 0)
        firstUse = nil
        #expect(returns == 0)
        secondUse = nil
        #expect(returns == 1)
    }

    @Test("An explicit release cannot invalidate another image alias")
    func explicitReleasePreservesAliases() throws {
        var returns = 0
        var image: FabricImage? = .managed(texture: try texture()) { _ in returns += 1 }
        var alias = image
        image?.release()
        image = nil
        #expect(alias != nil)
        #expect(returns == 0)
        alias = nil
        #expect(returns == 1)
    }

    @Test("Discarding unsubmitted work releases its GPU ownership")
    func abandonedUseReleasesStorage() throws {
        var returns = 0
        var image: FabricImage? = .managed(texture: try texture()) { _ in returns += 1 }
        var resources: GraphFrameImageUses? = GraphFrameImageUses()
        resources?.retain(try #require(image))
        image = nil
        #expect(returns == 0)
        resources = nil
        #expect(returns == 1)
    }

    @Test("Image storage in virtual nested collections is retained")
    func virtualCollectionsRetainTheirImages() throws {
        var returns = 0
        var image: FabricImage? = .managed(texture: try texture()) { _ in returns += 1 }
        let port = NodePort<PortValue>(name: "Images", kind: .Outlet)
        port.value = .Dictionary(["history": .Array([.Image(try #require(image))])])
        var resources: GraphFrameImageUses? = GraphFrameImageUses()
        resources?.retainImages(in: [port])
        port.value = nil
        image = nil
        #expect(returns == 0)
        resources = nil
        #expect(returns == 1)
    }
}
