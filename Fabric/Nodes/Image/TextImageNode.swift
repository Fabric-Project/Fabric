import Foundation
import Satin
import simd
import Metal
import MetalKit
import ImageIO

public final class TextImageNode: Node
{
    public override class var name: String { "Text Image" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .Generator) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Renders MSDF text from atlas-runtime metadata to an image" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputText", ParameterPort(parameter: StringParameter("Text", "Fabric", .inputfield, "Text content to render"))),
            ("inputAtlasJSONPath", ParameterPort(parameter: StringParameter("Runtime JSON Path", "", .filepicker, "Path to *-atlas-runtime.json, or an export folder containing it"))),
            ("inputAtlasTexturePath", ParameterPort(parameter: StringParameter("Atlas Texture Path", "", .filepicker, "Optional override path to atlas image. Leave empty to use runtime metadata imageFileName"))),
            ("inputWidth", ParameterPort(parameter: IntParameter("Width", 1920, 1, 8192, .inputfield, "Output image width in pixels"))),
            ("inputHeight", ParameterPort(parameter: IntParameter("Height", 1080, 1, 8192, .inputfield, "Output image height in pixels"))),
            ("inputScale", ParameterPort(parameter: FloatParameter("Scale", 1.0, 0.001, 128.0, .inputfield, "Scale multiplier for glyph pixel bounds"))),
            ("inputAlignment", ParameterPort(parameter: StringParameter("Alignment", "Center", ["Left", "Center", "Right"], .dropdown, "Horizontal alignment for text placement"))),
            ("inputColor", ParameterPort(parameter: Float4Parameter("Color", .one, .zero, .one, .colorpicker, "Text color (RGBA)"))),
            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Rendered text image")),
        ]
    }

    public var inputText: ParameterPort<String> { port(named: "inputText") }
    public var inputAtlasJSONPath: ParameterPort<String> { port(named: "inputAtlasJSONPath") }
    public var inputAtlasTexturePath: ParameterPort<String> { port(named: "inputAtlasTexturePath") }
    public var inputWidth: ParameterPort<Int> { port(named: "inputWidth") }
    public var inputHeight: ParameterPort<Int> { port(named: "inputHeight") }
    public var inputScale: ParameterPort<Float> { port(named: "inputScale") }
    public var inputAlignment: ParameterPort<String> { port(named: "inputAlignment") }
    public var inputColor: ParameterPort<simd_float4> { port(named: "inputColor") }
    public var outputTexturePort: NodePort<FabricImage> { port(named: "outputTexturePort") }

    @ObservationIgnored private var pipelineState: MTLRenderPipelineState?
    @ObservationIgnored private var samplerState: MTLSamplerState?
    @ObservationIgnored private var pipelinePixelFormat: MTLPixelFormat?

    @ObservationIgnored private var loadedBundle: RuntimeAtlasBundle?
    @ObservationIgnored private var loadedRuntimeMetadataURL: URL?
    @ObservationIgnored private var loadedAtlasTextureURL: URL?
    @ObservationIgnored private var loadedAtlasTexture: MTLTexture?

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let width = max(1, self.inputWidth.value ?? 1920)
        let height = max(1, self.inputHeight.value ?? 1080)

        guard let outputImage = context.graphRenderer?.newImage(withWidth: width, height: height) else {
            self.outputTexturePort.send(nil)
            return
        }

        guard self.loadRuntimeBundleIfNeeded() else {
            self.outputTexturePort.send(nil)
            return
        }

        guard self.setupPipelineIfNeeded(pixelFormat: outputImage.texture.pixelFormat) else {
            self.outputTexturePort.send(nil)
            return
        }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = outputImage.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            self.outputTexturePort.send(nil)
            return
        }

        defer {
            encoder.endEncoding()
        }

        guard let pipelineState = self.pipelineState,
              let samplerState = self.samplerState,
              let atlasBundle = self.loadedBundle,
              let atlasTexture = self.loadedAtlasTexture
        else {
            self.outputTexturePort.send(outputImage)
            return
        }

        let instances = self.buildGlyphInstances(bundle: atlasBundle, width: width, height: height)
        guard instances.isEmpty == false else {
            self.outputTexturePort.send(outputImage)
            return
        }

        let instanceByteLength = MemoryLayout<GlyphInstance>.stride * instances.count
        guard let instanceBuffer = instances.withUnsafeBytes({ bytes -> MTLBuffer? in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return self.context.device.makeBuffer(bytes: baseAddress,
                                                  length: instanceByteLength,
                                                  options: .storageModeShared)
        }) else {
            self.outputTexturePort.send(outputImage)
            return
        }

        var uniforms = MSDFUniforms(viewportSize: SIMD2<Float>(Float(width), Float(height)),
                                    distanceRange: Float(atlasBundle.metadata.atlas.distanceRange),
                                    padding: Float(atlasBundle.metadata.atlas.padding))

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<MSDFUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MSDFUniforms>.stride, index: 0)
        encoder.setFragmentTexture(atlasTexture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instances.count)

        self.outputTexturePort.send(outputImage)
    }
}

// MARK: - Runtime Bundle
extension TextImageNode
{
    private func loadRuntimeBundleIfNeeded() -> Bool
    {
        guard let inputURL = self.makeURL(from: self.inputAtlasJSONPath.value) else {
            self.resetLoadedResources()
            return false
        }

        guard let runtimeMetadataURL = self.resolveRuntimeMetadataURL(from: inputURL) else {
            self.resetLoadedResources()
            return false
        }

        guard let metadata = self.decodeRuntimeMetadata(from: runtimeMetadataURL) else {
            self.resetLoadedResources()
            return false
        }

        let resolvedAtlasTextureURL: URL
        if let overrideURL = self.makeURL(from: self.inputAtlasTexturePath.value) {
            resolvedAtlasTextureURL = overrideURL
        } else {
            resolvedAtlasTextureURL = runtimeMetadataURL
                .deletingLastPathComponent()
                .appendingPathComponent(metadata.atlas.imageFileName)
        }

        let shouldReload = self.loadedBundle == nil
            || self.loadedRuntimeMetadataURL != runtimeMetadataURL
            || self.loadedAtlasTextureURL != resolvedAtlasTextureURL

        guard shouldReload else { return true }

        guard let atlasTexture = self.loadAtlasTexture(from: resolvedAtlasTextureURL) else {
            self.resetLoadedResources()
            return false
        }

        self.loadedBundle = RuntimeAtlasBundle(metadata: metadata, runtimeMetadataURL: runtimeMetadataURL, atlasImageURL: resolvedAtlasTextureURL)
        self.loadedRuntimeMetadataURL = runtimeMetadataURL
        self.loadedAtlasTextureURL = resolvedAtlasTextureURL
        self.loadedAtlasTexture = atlasTexture
        return true
    }

    private func resolveRuntimeMetadataURL(from inputURL: URL) -> URL?
    {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: inputURL.path(percentEncoded: false), isDirectory: &isDirectory)
        guard exists else { return nil }

        if isDirectory.boolValue {
            let defaultRuntime = inputURL.appendingPathComponent("atlas-runtime.json")
            if fileManager.fileExists(atPath: defaultRuntime.path(percentEncoded: false)) {
                return defaultRuntime.standardizedFileURL
            }

            guard let folderContents = try? fileManager.contentsOfDirectory(at: inputURL, includingPropertiesForKeys: nil),
                  let runtimeJSON = folderContents.first(where: { $0.lastPathComponent.hasSuffix("-atlas-runtime.json") }) else {
                return nil
            }

            return runtimeJSON.standardizedFileURL
        }

        return inputURL.standardizedFileURL
    }

    private func decodeRuntimeMetadata(from runtimeMetadataURL: URL) -> RuntimeAtlasMetadata?
    {
        guard let data = try? Data(contentsOf: runtimeMetadataURL) else { return nil }
        return try? JSONDecoder().decode(RuntimeAtlasMetadata.self, from: data)
    }

    private func loadAtlasTexture(from atlasTextureURL: URL) -> MTLTexture?
    {
        guard let source = CGImageSourceCreateWithURL(atlasTextureURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .generateMipmaps: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
        ]

        let loader = MTKTextureLoader(device: self.context.device)
        return try? loader.newTexture(cgImage: cgImage, options: options)
    }

    private func resetLoadedResources()
    {
        self.loadedBundle = nil
        self.loadedRuntimeMetadataURL = nil
        self.loadedAtlasTextureURL = nil
        self.loadedAtlasTexture = nil
    }

    private func makeURL(from rawPath: String?) -> URL?
    {
        guard let rawPath, rawPath.isEmpty == false else { return nil }

        if let parsedURL = URL(string: rawPath), parsedURL.scheme != nil {
            return parsedURL.standardizedFileURL
        }

        return URL(fileURLWithPath: rawPath).standardizedFileURL
    }
}

// MARK: - Pipeline
extension TextImageNode
{
    private func setupPipelineIfNeeded(pixelFormat: MTLPixelFormat) -> Bool
    {
        if self.pipelineState != nil, self.samplerState != nil, self.pipelinePixelFormat == pixelFormat {
            return true
        }

        guard let shaderURL = Bundle.module.url(forResource: "MSDFTextImage", withExtension: "metal", subdirectory: "Shaders") else {
            return false
        }

        let compiler = MetalFileCompiler(watch: false)
        guard let source = try? compiler.parse(shaderURL),
              let library = try? self.context.device.makeLibrary(source: source, options: nil),
              let vertexFunction = library.makeFunction(name: "msdf_node_vertex"),
              let fragmentFunction = library.makeFunction(name: "msdf_node_fragment") else {
            return false
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipelineState = try? self.context.device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            return false
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let samplerState = self.context.device.makeSamplerState(descriptor: samplerDescriptor) else {
            return false
        }

        self.pipelineState = pipelineState
        self.samplerState = samplerState
        self.pipelinePixelFormat = pixelFormat
        return true
    }
}

// MARK: - Glyph Layout
extension TextImageNode
{
    private func buildGlyphInstances(bundle: RuntimeAtlasBundle, width: Int, height: Int) -> [GlyphInstance]
    {
        let text = self.inputText.value ?? ""
        guard text.isEmpty == false else { return [] }

        let layoutScale = CGFloat(max(0.001, self.inputScale.value ?? 1.0))
        let color = self.inputColor.value ?? .one

        let characters = Array(text)
        var penX: CGFloat = 0
        var previousUnicode: Int?
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        var glyphRects: [(screen: CGRect, uv: CGRect)] = []

        for character in characters {
            guard let unicodeScalar = character.unicodeScalars.first else { continue }
            let unicode = Int(unicodeScalar.value)

            if let previousUnicode {
                penX += CGFloat(bundle.kerningAdvancePx(forLeftUnicode: previousUnicode, rightUnicode: unicode)) * layoutScale
            }

            guard let glyph = bundle.glyph(forUnicode: unicode) else {
                previousUnicode = unicode
                continue
            }

            if let planeBoundsPx = glyph.planeBoundsPx,
               let atlasUVRect = self.atlasUVRect(for: glyph, atlas: bundle.metadata.atlas) {
                let screenRect = CGRect(
                    x: penX + CGFloat(planeBoundsPx.left) * layoutScale,
                    y: CGFloat(planeBoundsPx.top) * layoutScale,
                    width: CGFloat(planeBoundsPx.right - planeBoundsPx.left) * layoutScale,
                    height: CGFloat(planeBoundsPx.bottom - planeBoundsPx.top) * layoutScale
                )

                glyphRects.append((screen: screenRect, uv: atlasUVRect))
                minX = min(minX, screenRect.minX)
                maxX = max(maxX, screenRect.maxX)
                minY = min(minY, screenRect.minY)
                maxY = max(maxY, screenRect.maxY)
            }

            penX += CGFloat(glyph.advancePx) * layoutScale
            previousUnicode = unicode
        }

        guard glyphRects.isEmpty == false else { return [] }

        let alignment = self.inputAlignment.value ?? "Center"
        let containerWidth = CGFloat(width)
        let containerHeight = CGFloat(height)
        let contentWidth = maxX - minX
        let contentHeight = maxY - minY

        let offsetX: CGFloat
        switch alignment {
        case "Left":
            offsetX = -minX
        case "Right":
            offsetX = containerWidth - maxX
        default:
            offsetX = (containerWidth - contentWidth) * 0.5 - minX
        }

        let offsetY = (containerHeight - contentHeight) * 0.5 - minY

        return glyphRects.map { glyph in
            let centeredScreenRect = glyph.screen.offsetBy(dx: offsetX, dy: offsetY)
            return GlyphInstance(screenRect: SIMD4<Float>(
                Float(centeredScreenRect.minX),
                Float(centeredScreenRect.minY),
                Float(centeredScreenRect.maxX),
                Float(centeredScreenRect.maxY)
            ), atlasUVRect: SIMD4<Float>(
                Float(glyph.uv.minX),
                Float(glyph.uv.minY),
                Float(glyph.uv.maxX),
                Float(glyph.uv.maxY)
            ), color: color)
        }
    }

    private func atlasUVRect(for glyph: RuntimeAtlasMetadata.Glyph, atlas: RuntimeAtlasMetadata.Atlas) -> CGRect?
    {
        if let uv = glyph.atlasBoundsUV {
            if atlas.yOrigin.lowercased() == "bottom" {
                return CGRect(x: uv.left, y: 1.0 - uv.bottom, width: uv.right - uv.left, height: uv.bottom - uv.top)
            }
            return CGRect(x: uv.left, y: uv.top, width: uv.right - uv.left, height: uv.bottom - uv.top)
        }

        guard let px = glyph.atlasBoundsPx, atlas.width > 0, atlas.height > 0 else {
            return nil
        }

        let left = px.left / Double(atlas.width)
        let right = px.right / Double(atlas.width)
        let top = px.top / Double(atlas.height)
        let bottom = px.bottom / Double(atlas.height)

        if atlas.yOrigin.lowercased() == "bottom" {
            return CGRect(x: left, y: 1.0 - bottom, width: right - left, height: bottom - top)
        }

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

// MARK: - Runtime Types
private struct RuntimeAtlasMetadata: Decodable
{
    struct Atlas: Decodable
    {
        let type: String
        let imageFileName: String
        let charsetFileName: String
        let yOrigin: String
        let width: Int
        let height: Int
        let distanceRange: Double
        let emSize: Double
        let pixelRange: Double
        let padding: Int
    }

    struct Metrics: Decodable
    {
        let lineHeightEm: Double
        let ascenderEm: Double
        let descenderEm: Double
        let underlineYEm: Double
        let underlineThicknessEm: Double
        let lineHeightPx: Double
        let ascenderPx: Double
        let descenderPx: Double
        let underlineYPx: Double
        let underlineThicknessPx: Double
    }

    struct Rect: Decodable
    {
        let left: Double
        let top: Double
        let right: Double
        let bottom: Double
    }

    struct Glyph: Decodable
    {
        let unicode: Int
        let character: String
        let advanceEm: Double
        let advancePx: Double
        let planeBoundsEm: Rect?
        let planeBoundsPx: Rect?
        let atlasBoundsPx: Rect?
        let atlasBoundsUV: Rect?
    }

    struct KerningPair: Decodable
    {
        let unicode1: Int
        let unicode2: Int
        let character1: String
        let character2: String
        let advanceEm: Double
        let advancePx: Double
    }

    let version: Int
    let atlas: Atlas
    let metrics: Metrics
    let glyphs: [Glyph]
    let kerning: [KerningPair]
}

private struct RuntimeAtlasBundle
{
    let metadata: RuntimeAtlasMetadata
    let runtimeMetadataURL: URL
    let atlasImageURL: URL

    private let glyphsByUnicode: [Int: RuntimeAtlasMetadata.Glyph]
    private let kerningByPair: [UInt64: Double]

    init(metadata: RuntimeAtlasMetadata, runtimeMetadataURL: URL, atlasImageURL: URL)
    {
        self.metadata = metadata
        self.runtimeMetadataURL = runtimeMetadataURL
        self.atlasImageURL = atlasImageURL

        var glyphLookup: [Int: RuntimeAtlasMetadata.Glyph] = [:]
        glyphLookup.reserveCapacity(metadata.glyphs.count)
        for glyph in metadata.glyphs {
            glyphLookup[glyph.unicode] = glyph
        }
        self.glyphsByUnicode = glyphLookup

        var kerningLookup: [UInt64: Double] = [:]
        kerningLookup.reserveCapacity(metadata.kerning.count)
        for kerningPair in metadata.kerning {
            let key = RuntimeAtlasBundle.kerningKey(leftUnicode: kerningPair.unicode1, rightUnicode: kerningPair.unicode2)
            kerningLookup[key] = kerningPair.advancePx
        }
        self.kerningByPair = kerningLookup
    }

    func glyph(forUnicode unicode: Int) -> RuntimeAtlasMetadata.Glyph?
    {
        self.glyphsByUnicode[unicode]
    }

    func kerningAdvancePx(forLeftUnicode leftUnicode: Int, rightUnicode: Int) -> Double
    {
        let key = RuntimeAtlasBundle.kerningKey(leftUnicode: leftUnicode, rightUnicode: rightUnicode)
        return self.kerningByPair[key] ?? 0
    }

    private static func kerningKey(leftUnicode: Int, rightUnicode: Int) -> UInt64
    {
        let left = UInt64(UInt32(truncatingIfNeeded: leftUnicode))
        let right = UInt64(UInt32(truncatingIfNeeded: rightUnicode))
        return (left << 32) | right
    }
}

private struct GlyphInstance
{
    var screenRect: SIMD4<Float>
    var atlasUVRect: SIMD4<Float>
    var color: SIMD4<Float>
}

private struct MSDFUniforms
{
    var viewportSize: SIMD2<Float>
    var distanceRange: Float
    var padding: Float
}
