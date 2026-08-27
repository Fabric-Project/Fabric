import Testing
import Foundation
import Satin
@testable import Fabric

@Suite("Lygia Include Resolution", .serialized)
struct LygiaIncludeResolutionTests {

    /// The compiler's fallback, against a root built here so the test
    /// controls both sides of the resolution.
    ///
    /// The nested include also pins that once the fallback lands inside the
    /// root, a lygia file's own relative includes continue from there.
    @Test("A lygia include resolves against the injected root")
    func lygiaIncludeResolvesAgainstInjectedRoot() throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }

        // The root's directory name is its key: it must match the include's
        // leading component. The unrelated root ahead of it pins that a
        // non-matching root is skipped, not blindly taken.
        let root = base.appending(path: "lygia")
        try FileManager.default.createDirectory(
            at: root.appending(path: "color/space"), withIntermediateDirectories: true)
        try "#define FNC_LUMINANCE\n".write(
            to: root.appending(path: "color/luminance.msl"),
            atomically: true, encoding: .utf8)
        try "#include \"../luminance.msl\"\n#define FNC_LINEAR2GAMMA\n".write(
            to: root.appending(path: "color/space/linear2gamma.msl"),
            atomically: true, encoding: .utf8)

        // A "Library" component in the shader's own path pins the fallback
        // ordering: the lygia branch must win over the Library one, or an app
        // running from ~/Library never resolves a lygia include.
        let shaderDir = base.appending(path: "Library/shader")
        try FileManager.default.createDirectory(at: shaderDir,
                                                withIntermediateDirectories: true)
        let shaderURL = shaderDir.appending(path: "Standalone.metal")
        try "#include \"lygia/color/space/linear2gamma.msl\"\n".write(
            to: shaderURL, atomically: true, encoding: .utf8)

        let previousRoots = shaderIncludeRootURLs
        shaderIncludeRootURLs = [base.appending(path: "unrelated"), root]
        defer { shaderIncludeRootURLs = previousRoots }

        let source = try MetalFileCompiler(watch: false).parse(shaderURL)
        #expect(source.contains("FNC_LINEAR2GAMMA"),
                "The lygia include should expand from the injected root")
        #expect(source.contains("FNC_LUMINANCE"),
                "The included file's own relative include should expand too")
    }

    @Test("Loading the core plugin injects Fabric's lygia root")
    func corePluginLoadInjectsLygiaRoot() throws {
        try PluginLoader.shared.loadAllPlugins()

        let root = try #require(
            shaderIncludeRootURLs.first(where: { $0.lastPathComponent == "lygia" }),
            "Core plugin load should hand Satin the lygia root")
        #expect(FileManager.default.fileExists(
            atPath: root.appending(path: "sampler.msl").path(percentEncoded: false)),
                "The injected root should hold the shipped lygia tree")
    }
}
