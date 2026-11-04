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

/// What a document says about a graph, as a comparable value: each node's
/// type and ports, the wires and publishing by address, every parameter
/// inlet's value, and inner graphs by their node.
private struct GraphShape: Equatable
{
    struct PortShape: Equatable { let type: String; let isInlet: Bool }

    var nodeTypes: [UUID: String] = [:]
    var ports: [PortAddress: PortShape] = [:]
    var connections: Set<String> = []
    var published: [String] = []
    var values: [PortAddress: String] = [:]
    var inner: [UUID: GraphShape] = [:]

    init(_ graph: Graph)
    {
        for node in graph.nodes
        {
            nodeTypes[node.id] = String(describing: type(of: node))
            for port in node.ports
            {
                let address = PortAddress(node: node.id, key: port.key)
                ports[address] = PortShape(type: port.portType.rawValue, isInlet: port.kind == .Inlet)
            }
            for state in node.registry.states()
            {
                values[PortAddress(node: node.id, key: state.key)] = "\(state.value)"
            }
            if let subgraph = node as? SubgraphNode { inner[node.id] = GraphShape(subgraph.subGraph) }
        }
        for connection in graph.connections
        {
            guard let outlet = connection.outletPort.flatMap(graph.address(of:)),
                  let inlet = connection.inletPort.flatMap(graph.address(of:))
            else { continue }
            connections.insert("\(outlet) -> \(inlet) \(connection.active)")
        }
        published = graph.publishedPortEntries.map { "\($0.address) \($0.name ?? "-")" }
    }
}

/// What an old document holds, read from its JSON as the old format had it.
private struct LegacyShape
{
    var connectionCount = 0
    var publishedCount = 0
    /// Parameter inlet values by node id and key.
    var values: [UUID: [String: Any]] = [:]
    var inner: [UUID: LegacyShape] = [:]

    init(_ json: [String: Any])
    {
        if let connections = json["connections"] as? [[String: Any]]
        {
            connectionCount = connections.count
        }
        else if let map = json["portConnectionMap"] as? [String: [String]]
        {
            var pairs = Set<Set<String>>()
            for (port, others) in map { for other in others { pairs.insert([port, other]) } }
            connectionCount = pairs.count
        }

        for entry in json["nodeMap"] as? [[String: Any]] ?? []
        {
            guard let value = entry["value"] as? [String: Any],
                  let id = (value["id"] as? String).flatMap(UUID.init(uuidString:))
            else { continue }

            var envelopes: [(key: String, base: [String: Any], isParameter: Bool)] = []
            for snapshot in value["ports"] as? [[String: Any]] ?? []
            {
                guard let key = snapshot["name"] as? String,
                      let payload = snapshot["payload"] as? [String: Any],
                      let base = payload["base"] as? [String: Any]
                else { continue }
                envelopes.append((key, base, payload["isParameterPort"] as? Bool ?? false))
            }
            for (key, saved) in value
            {
                guard let base = saved as? [String: Any], base["kind"] is String, base["id"] is String else { continue }
                envelopes.append((key, base, base["parameter"] != nil))
            }
            for proxy in value["proxyPorts"] as? [[String: Any]] ?? []
            {
                if (proxy["base"] as? [String: Any])?["published"] as? Bool == true { publishedCount += 1 }
            }

            for envelope in envelopes
            {
                if envelope.base["published"] as? Bool == true { publishedCount += 1 }
                guard envelope.isParameter,
                      let parameter = envelope.base["parameter"] as? [String: Any],
                      parameter["type"] as? String != "generic",
                      let saved = (parameter["base"] as? [String: Any])?["value"]
                else { continue }
                values[id, default: [:]][envelope.key] = saved
            }

            if let subGraph = value["subGraph"] as? [String: Any] { inner[id] = LegacyShape(subGraph) }
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

    /// The reader for documents saved before ports were addressed, checked
    /// against every sample: what the old document held arrives, and a save in
    /// the current format then loads back as the same graph.
    @Test("Every sample migrates, and survives a save in the current format", arguments: FabricSampleCatalog.samples)
    func everySampleMigratesAndRoundTrips(_ fixture: FabricSampleFixture) throws
    {
        let context = try FabricSampleTestSupport.makeContext()
        let loaded = try FabricSampleTestSupport.load(fixture, context: context)
        try Self.expect(loaded.graph, holds: LegacyShape(loaded.serializedGraph), path: fixture.relativePath)

        let saved = try JSONEncoder().encode(loaded.graph)
        let savedJSON = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        #expect(savedJSON["portConnectionMap"] == nil)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context,
                                         fileReferenceBaseURL: fixture.documentURL.deletingLastPathComponent())
        let reloaded = try decoder.decode(Graph.self, from: saved)

        #expect(GraphShape(reloaded) == GraphShape(loaded.graph), "\(fixture.relativePath) changed across a save")
        #expect(reloaded.droppedConnectionDiagnostics.isEmpty)
        #expect(reloaded.droppedPortStateDiagnostics.isEmpty)
    }

    private static func expect(_ graph: Graph, holds legacy: LegacyShape, path: String) throws
    {
        // A wire either arrives or is reported dropped; none disappears.
        #expect(graph.connections.count + graph.droppedConnectionDiagnostics.count == legacy.connectionCount,
                "\(path): \(graph.connections.count) wires and \(graph.droppedConnectionDiagnostics.count) dropped of \(legacy.connectionCount)")
        if graph.missingNodeDiagnostics.isEmpty
        {
            #expect(graph.publishedPortEntries.count == legacy.publishedCount, "\(path): published")
        }

        for (nodeID, values) in legacy.values
        {
            guard let node = graph.node(forID: nodeID) else { continue }
            for (key, saved) in values
            {
                guard let port = node.port(forKey: .own(key)), let value = port.snapshotValue() else { continue }
                // A slider clamps a value its range no longer holds, as decode always has.
                if port.control == .slider, case .Float = value { continue }
                #expect(Self.matches(value, saved), "\(path): \(node.title).\(key) is \(value), saved \(saved)")
            }
        }

        for (nodeID, inner) in legacy.inner
        {
            guard let subgraph = graph.node(forID: nodeID) as? SubgraphNode else { continue }
            try expect(subgraph.subGraph, holds: inner, path: "\(path)/\(subgraph.title)")
        }
    }

    /// Whether a loaded value is the one the old document saved.
    private static func matches(_ value: PortValue, _ saved: Any) -> Bool
    {
        func floats(_ any: Any) -> [Float]? { (any as? [Any])?.compactMap { ($0 as? NSNumber)?.floatValue } }
        // A vector saved with another width, a float3 color now declared
        // float4 say, does not fit the port: the port keeps its default.
        func near(_ a: [Float], _ b: [Float]) -> Bool { a.count != b.count || zip(a, b).allSatisfy { abs($0 - $1) < 1e-5 } }

        switch value
        {
        case .Bool(let v): return (saved as? Bool) == v
        case .Int(let v): return (saved as? NSNumber)?.intValue == v
        case .Float(let v): return (saved as? NSNumber).map { abs($0.floatValue - v) < 1e-5 } ?? false
        case .String(let v): return (saved as? String) == v
        case .Vector2(let v): return floats(saved).map { near($0, [v.x, v.y]) } ?? false
        case .Vector3(let v): return floats(saved).map { near($0, [v.x, v.y, v.z]) } ?? false
        case .Vector4(let v): return floats(saved).map { near($0, [v.x, v.y, v.z, v.w]) } ?? false
        case .Transform(let m):
            let columns = (saved as? [Any])?.compactMap(floats) ?? []
            return columns.count == 4 && near(columns.flatMap { $0 },
                                              [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] })
        default: return true
        }
    }

    /// #449: execute reads ports through references bound at reconcile, and
    /// changes no node's interface.
    @Test("Rendering a sample looks no port up by key and reconciles nothing during execute", arguments: FabricSampleCatalog.samples)
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
