import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
@testable import Fabric
import Satin

struct FabricSampleFixture: Sendable, CustomTestStringConvertible
{
    let documentURL: URL
    let relativePath: String

    var testDescription: String { self.relativePath }

    var referenceURL: URL
    {
        FabricSampleCatalog.referenceRootURL
            .appending(path: self.relativePath)
            .deletingPathExtension()
            .appendingPathExtension("png")
    }
}

private enum FabricSampleCatalog
{
    static let repositoryRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    static let samplesRootURL = repositoryRootURL.appending(path: "Fabric-Samples/Samples", directoryHint: .isDirectory)
    static let referenceRootURL = repositoryRootURL.appending(path: "Tests/Resources/FabricSampleReferences", directoryHint: .isDirectory)

    static let samples: [FabricSampleFixture] =
    {
        guard let enumerator = FileManager.default.enumerator(
            at: samplesRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "fabric" }
            .map { documentURL in
                FabricSampleFixture(
                    documentURL: documentURL,
                    relativePath: String(documentURL.path.dropFirst(samplesRootURL.path.count + 1))
                )
            }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }()

    /// The samples are a submodule apps that depend on Fabric never fetch.
    static var isAvailable: Bool { !samples.isEmpty }

    static let unavailableComment: Comment = "Fabric-Samples is not checked out. Run: git submodule update --init --checkout Fabric-Samples"

    /// Recording writes every reference; otherwise only samples with a reference are compared.
    static var samplesToCompare: [FabricSampleFixture]
    {
        if FabricSampleTestSupport.isRecordingReferences { return samples }
        return samples.filter { FileManager.default.fileExists(atPath: $0.referenceURL.path) }
    }
}

private struct FabricSampleTestError: Error, CustomStringConvertible
{
    let description: String

    init(_ description: String)
    {
        self.description = description
    }
}

private struct FabricSampleImage
{
    let width: Int
    let height: Int
    let pixels: [UInt8]
}

private struct FabricSampleImageDifference
{
    let meanAbsoluteDifference: Double
    let maximumAbsoluteDifference: UInt8
    let differingPixelCount: Int
    let image: FabricSampleImage
}

private enum FabricSampleTestSupport
{
    static let renderSize = (width: 640, height: 480)
    static let renderTime: TimeInterval = 1.0
    static let referenceRecordingEnvironmentKey = "FABRIC_RECORD_REFERENCE_IMAGES"
    static let maximumMeanAbsoluteDifference = 0.005
    static let failureArtifactsRootURL = URL.temporaryDirectory
        .appending(path: "FabricSampleVisualDiffs", directoryHint: .isDirectory)

    static var isRecordingReferences: Bool
    {
        ProcessInfo.processInfo.environment[referenceRecordingEnvironmentKey] == "1"
    }

    static func makeContext() throws -> Context
    {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw FabricSampleTestError("Metal is unavailable")
        }

        return Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .rgba16Float,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .stencil8,
            alphaOitEnabled: true
        )
    }

    static func load(_ fixture: FabricSampleFixture, context: Context) throws -> (graph: Graph, serializedGraph: [String: Any])
    {
        let data = try Data(contentsOf: fixture.documentURL)
        guard let serializedGraph = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FabricSampleTestError("\(fixture.relativePath) is not a graph JSON object")
        }

        let decoder = JSONDecoder()
        // As the editor does: file references resolve against the document's folder.
        decoder.context = DecoderContext(documentContext: context,
                                         fileReferenceBaseURL: fixture.documentURL.deletingLastPathComponent())
        return (try decoder.decode(Graph.self, from: data), serializedGraph)
    }

    static func validateLoadedGraph(_ graph: Graph, serializedGraph: [String: Any], path: String) throws
    {
        guard let serializedNodes = serializedGraph["nodeMap"] as? [[String: Any]] else {
            throw FabricSampleTestError("\(path) has no nodeMap")
        }

        let serializedNodesByID = try Dictionary(uniqueKeysWithValues: serializedNodes.map { serializedNode in
            guard let value = serializedNode["value"] as? [String: Any],
                  let idString = value["id"] as? String,
                  let id = UUID(uuidString: idString)
            else {
                throw FabricSampleTestError("\(path) contains a node without a valid UUID")
            }

            return (id, value)
        })
        let loadedNodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })

        guard Set(serializedNodesByID.keys) == Set(loadedNodesByID.keys) else {
            let missingNodeIDs = Set(serializedNodesByID.keys).subtracting(loadedNodesByID.keys)
            let unexpectedNodeIDs = Set(loadedNodesByID.keys).subtracting(serializedNodesByID.keys)
            throw FabricSampleTestError(
                "\(path) loaded a different node set; missing: \(missingNodeIDs), unexpected: \(unexpectedNodeIDs)"
            )
        }

        guard graph.droppedPortStateDiagnostics.isEmpty else {
            let diagnostics = graph.droppedPortStateDiagnostics.map {
                "\($0.nodeTitle) dropped \($0.droppedRegistryKeys.joined(separator: ", "))"
            }
            throw FabricSampleTestError("\(path) dropped saved port state: \(diagnostics.joined(separator: "; "))")
        }

        guard graph.droppedConnectionDiagnostics.isEmpty else {
            let diagnostics = graph.droppedConnectionDiagnostics.map(\.summary)
            throw FabricSampleTestError("\(path) dropped saved connections: \(diagnostics.joined(separator: "; "))")
        }

        for connection in graph.connections
        {
            guard connection.graph === graph,
                  let outletPort = connection.outletPort,
                  let inletPort = connection.inletPort,
                  outletPort.node?.graph === graph,
                  inletPort.node?.graph === graph,
                  outletPort.connections.contains(where: { $0 === connection }),
                  inletPort.connections.contains(where: { $0 === connection })
            else {
                throw FabricSampleTestError("\(path) contains connection \(connection.id) with inconsistent graph ownership")
            }
        }

        for (nodeID, serializedNode) in serializedNodesByID
        {
            guard let serializedSubgraph = serializedNode["subGraph"] as? [String: Any] else { continue }
            guard let subgraphNode = loadedNodesByID[nodeID] as? SubgraphNode else {
                throw FabricSampleTestError("\(path) serialized node \(nodeID) as a subgraph but decoded another node type")
            }

            try validateLoadedGraph(
                subgraphNode.subGraph,
                serializedGraph: serializedSubgraph,
                path: "\(path)/\(subgraphNode.title)"
            )
        }
    }

    static func render(_ graph: Graph, context: Context) throws -> FabricSampleImage
    {
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.colorPixelFormat,
            width: renderSize.width,
            height: renderSize.height,
            mipmapped: false
        )
        colorDescriptor.usage = [.renderTarget, .shaderRead]

        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.depthPixelFormat,
            width: renderSize.width,
            height: renderSize.height,
            mipmapped: false
        )
        depthDescriptor.storageMode = .private
        depthDescriptor.usage = [.renderTarget]

        guard let colorTexture = context.device.makeTexture(descriptor: colorDescriptor),
              let depthTexture = context.device.makeTexture(descriptor: depthDescriptor)
        else {
            throw FabricSampleTestError("Failed to create 640×480 sample render targets")
        }

        let renderer = GraphExportRenderer(graph: graph, context: context, size: renderSize)
        try renderer.renderSingleFrame(into: colorTexture, depthTexture: depthTexture, time: renderTime)

        let sourceColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let coreImageContext = CIContext(mtlDevice: context.device)
        let bounds = CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height)

        guard let coreImage = CIImage(
            mtlTexture: colorTexture,
            options: [CIImageOption.colorSpace: sourceColorSpace]
        ),
              let image = coreImageContext.createCGImage(
                coreImage,
                from: bounds,
                format: .BGRA8,
                colorSpace: outputColorSpace
              )
        else {
            throw FabricSampleTestError("Failed to read the rendered sample image")
        }

        return try makeImage(from: image)
    }

    static func assertMatchesReference(_ renderedImage: FabricSampleImage, fixture: FabricSampleFixture) throws
    {
        if isRecordingReferences
        {
            try FileManager.default.createDirectory(
                at: fixture.referenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try writePNG(renderedImage, to: fixture.referenceURL)
            return
        }

        guard FileManager.default.fileExists(atPath: fixture.referenceURL.path) else {
            throw FabricSampleTestError(
                "Missing reference image for \(fixture.relativePath). Record it with \(referenceRecordingEnvironmentKey)=1."
            )
        }

        let referenceImage = try loadImage(at: fixture.referenceURL)
        guard renderedImage.width == referenceImage.width,
              renderedImage.height == referenceImage.height
        else {
            throw FabricSampleTestError(
                "\(fixture.relativePath) rendered at \(renderedImage.width)×\(renderedImage.height), but its reference is \(referenceImage.width)×\(referenceImage.height)"
            )
        }

        let difference = makeDifference(renderedImage, referenceImage)
        guard difference.meanAbsoluteDifference <= maximumMeanAbsoluteDifference else {
            let artifactDirectory = failureArtifactsRootURL
                .appending(path: fixture.relativePath)
                .deletingPathExtension()
            try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)

            let actualURL = artifactDirectory.appending(path: "actual.png")
            let differenceURL = artifactDirectory.appending(path: "difference.png")
            try writePNG(renderedImage, to: actualURL)
            try writePNG(difference.image, to: differenceURL)

            throw FabricSampleTestError(
                """
                \(fixture.relativePath) differs from its reference.
                Mean absolute difference: \(difference.meanAbsoluteDifference) (maximum \(maximumMeanAbsoluteDifference))
                Maximum channel difference: \(difference.maximumAbsoluteDifference)
                Differing pixels: \(difference.differingPixelCount)/\(renderedImage.width * renderedImage.height)
                Actual: \(actualURL.path)
                Difference: \(differenceURL.path)
                """
            )
        }
    }

    private static func loadImage(at url: URL) throws -> FabricSampleImage
    {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw FabricSampleTestError("Failed to load reference image at \(url.path)")
        }

        return try makeImage(from: image)
    }

    private static func makeImage(from image: CGImage) throws -> FabricSampleImage
    {
        let bytesPerRow = image.width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FabricSampleTestError("Failed to create a sample image bitmap context")
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return FabricSampleImage(width: image.width, height: image.height, pixels: pixels)
    }

    private static func makeDifference(
        _ renderedImage: FabricSampleImage,
        _ referenceImage: FabricSampleImage
    ) -> FabricSampleImageDifference
    {
        let pixelCount = renderedImage.width * renderedImage.height
        var totalDifference = 0
        var maximumDifference = 0
        var differingPixelCount = 0
        var differencePixels = [UInt8](repeating: 0, count: pixelCount * 4)

        for pixelIndex in 0..<pixelCount
        {
            let pixelOffset = pixelIndex * 4
            var maximumPixelDifference = 0

            for channel in 0..<4
            {
                let difference = abs(
                    Int(renderedImage.pixels[pixelOffset + channel])
                        - Int(referenceImage.pixels[pixelOffset + channel])
                )
                totalDifference += difference
                maximumDifference = max(maximumDifference, difference)
                maximumPixelDifference = max(maximumPixelDifference, difference)
            }

            if maximumPixelDifference > 0 {
                differingPixelCount += 1
            }

            differencePixels[pixelOffset] = UInt8(maximumPixelDifference)
            differencePixels[pixelOffset + 3] = 255
        }

        return FabricSampleImageDifference(
            meanAbsoluteDifference: Double(totalDifference) / Double(pixelCount * 4 * 255),
            maximumAbsoluteDifference: UInt8(maximumDifference),
            differingPixelCount: differingPixelCount,
            image: FabricSampleImage(
                width: renderedImage.width,
                height: renderedImage.height,
                pixels: differencePixels
            )
        )
    }

    private static func writePNG(_ image: FabricSampleImage, to url: URL) throws
    {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(image.pixels) as CFData),
              let image = CGImage(
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              )
        else {
            throw FabricSampleTestError("Failed to create PNG destination at \(url.path)")
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FabricSampleTestError("Failed to write PNG at \(url.path)")
        }
    }
}

@Suite("Fabric Samples", .serialized, .enabled(if: FabricSampleCatalog.isAvailable, FabricSampleCatalog.unavailableComment))
struct FabricSampleTests
{
    @Test("Sample catalog is present")
    func sampleCatalogIsPresent() throws
    {
        #expect(FileManager.default.fileExists(atPath: FabricSampleCatalog.samplesRootURL.path))
        #expect(!FabricSampleCatalog.samples.isEmpty)
    }

    @Test("Every sample loads without missing graph state", arguments: FabricSampleCatalog.samples)
    func everySampleLoads(_ fixture: FabricSampleFixture) throws
    {
        let context = try FabricSampleTestSupport.makeContext()
        let loaded = try FabricSampleTestSupport.load(fixture, context: context)
        try FabricSampleTestSupport.validateLoadedGraph(
            loaded.graph,
            serializedGraph: loaded.serializedGraph,
            path: fixture.relativePath
        )
    }

    /// #449: execute reads ports through references bound at reconcile.
    @Test("Rendering a sample looks no port up by key during execute", arguments: FabricSampleCatalog.samples)
    func renderingLooksNoPortUp(_ fixture: FabricSampleFixture) throws
    {
        let context = try FabricSampleTestSupport.makeContext()
        let loaded = try FabricSampleTestSupport.load(fixture, context: context)
        _ = Node.takeExecuteTimeLookups()
        _ = try? FabricSampleTestSupport.render(loaded.graph, context: context)
        _ = try? FabricSampleTestSupport.render(loaded.graph, context: context)
        let lookups = Node.takeExecuteTimeLookups()
        #expect(lookups.isEmpty, "\(Set(lookups).sorted())")
    }

    @Test("Every sample matches its 640×480 reference", arguments: FabricSampleCatalog.samplesToCompare)
    func everySampleMatchesItsReference(_ fixture: FabricSampleFixture) throws
    {
        let context = try FabricSampleTestSupport.makeContext()
        let loaded = try FabricSampleTestSupport.load(fixture, context: context)
        let renderedImage = try FabricSampleTestSupport.render(loaded.graph, context: context)
        try FabricSampleTestSupport.assertMatchesReference(renderedImage, fixture: fixture)
    }
}
