import Testing
import Foundation
import Metal
import Satin
@testable import Fabric

@Suite("Fabric Shader Include", .serialized)
struct FabricShaderIncludeTests {

    /// A shader outside Fabric's bundle — a plugin's — reaches the shared
    /// image helpers by the `fabric/` key, against the root the core plugin
    /// registers, and the result compiles.
    @Test("A plugin shader includes the texture transform helper by its fabric key")
    func pluginShaderIncludesTextureTransformHelper() throws {
        try PluginLoader.shared.loadAllPlugins()

        let base = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let shaderURL = base.appending(path: "Plugin.metal")
        try """
        #include "fabric/FabricImageTextureTransform.metal"

        kernel void pluginSample(texture2d<float, access::sample> image [[texture(0)]],
                                 texture2d<float, access::write> output [[texture(1)]],
                                 constant float4x4 *imageTransforms [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]])
        {
            constexpr sampler s(filter::linear);
            const float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
            output.write(image.sample(s, fabricTextureCoordinate(imageTransforms[0], uv)), gid);
        }
        """.write(to: shaderURL, atomically: true, encoding: .utf8)

        let source = try MetalFileCompiler(watch: false).parse(shaderURL)
        #expect(source.contains("fabricTextureCoordinate(float4x4 textureTransform"),
                "The fabric include should expand from the registered root")

        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try device.makeLibrary(source: source, options: nil)
        #expect(library.makeFunction(name: "pluginSample") != nil)
    }
}
