import Testing
import Metal
import Satin
@testable import Fabric

@Suite("Fabric image storage lifetime")
struct FabricImageLifetimeTests {
    private func texture() throws -> MTLTexture {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        return try #require(device.makeTexture(descriptor: descriptor))
    }

    @Test("Dropping one reference cannot release an image another alias holds")
    func droppingAReferencePreservesAliases() throws {
        var returns = 0
        var image: FabricImage? = .managed(texture: try texture()) { _ in returns += 1 }
        var alias = image
        image = nil
        #expect(alias != nil)
        #expect(returns == 0)
        alias = nil
        #expect(returns == 1)
    }

}
