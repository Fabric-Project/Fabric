import Testing
import Foundation
import Metal
import CoreImage
@testable import Fabric
import Satin

private func publish(_ port: Fabric.Port, in graph: Graph) {
    port.published = true
    graph.rebuildPublishedParameterGroup()
}

private func floatPort(named name: String, kind: PortKind, on node: Node) throws -> NodePort<Float> {
    guard let port = node.ports.first(where: { $0.name == name && $0.kind == kind }) as? NodePort<Float> else {
        throw GraphExecutionTestFailure("Missing Float port named \(name)")
    }

    return port
}

private func intPort(named name: String, kind: PortKind, on node: Node) throws -> NodePort<Int> {
    guard let port = node.ports.first(where: { $0.name == name && $0.kind == kind }) as? NodePort<Int> else {
        throw GraphExecutionTestFailure("Missing Int port named \(name)")
    }

    return port
}

private func imagePort(named name: String, kind: PortKind, on node: Node) throws -> NodePort<FabricImage> {
    guard let port = node.ports.first(where: { $0.name == name && $0.kind == kind }) as? NodePort<FabricImage> else {
        throw GraphExecutionTestFailure("Missing FabricImage port named \(name)")
    }

    return port
}

private final class RecursiveArrayDictionaryPortNode: Node {
    override class var name: String { "Recursive Array Dictionary Port" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Test node for recursive collection port publishing." }

    static let recursivePortType: PortType = .Array(portType: .Dictionary(valueType: .Array(portType: .Float)))

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)] {
        super.registerPorts(context: context) + [
            ("output", recursivePortType.makeFreshPort(name: "Recursive", kind: .Outlet)),
        ]
    }

    required init(context: Context) {
        super.init(context: context)
    }

    required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
    }
}

private func requireValue<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw GraphExecutionTestFailure(message)
    }

    return value
}

private func expectEqual(_ lhs: Float?, _ rhs: Float, tolerance: Float = 0.0001) throws {
    let lhs = try requireValue(lhs, "Expected Float value")
    #expect(abs(lhs - rhs) <= tolerance)
}

private func expectEqual(_ lhs: simd_float3, _ rhs: simd_float3, tolerance: Float = 0.0001) {
    #expect(abs(lhs.x - rhs.x) <= tolerance)
    #expect(abs(lhs.y - rhs.y) <= tolerance)
    #expect(abs(lhs.z - rhs.z) <= tolerance)
}

private func expectEqual(_ lhs: simd_float3x3, _ rhs: simd_float3x3, tolerance: Float = 0.0001) {
    expectEqual(lhs.columns.0, rhs.columns.0, tolerance: tolerance)
    expectEqual(lhs.columns.1, rhs.columns.1, tolerance: tolerance)
    expectEqual(lhs.columns.2, rhs.columns.2, tolerance: tolerance)
}

private func expectEqual(_ lhs: simd_float4x4, _ rhs: simd_float4x4, tolerance: Float = 0.0001) {
    for column in 0..<4 {
        for row in 0..<4 {
            #expect(abs(lhs[column][row] - rhs[column][row]) <= tolerance)
        }
    }
}

private func roundTripGraphToTemporaryFile(_ graph: Graph, context: Context) throws -> Graph {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let data = try encoder.encode(graph)
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("fabric-graph-roundtrip-\(UUID().uuidString)")
        .appendingPathExtension("json")

    try data.write(to: fileURL)
    let loadedData = try Data(contentsOf: fileURL)

    let decoder = JSONDecoder()
    decoder.context = DecoderContext(documentContext: context)

    return try decoder.decode(Graph.self, from: loadedData)
}

@Suite("Graph Execution")
struct GraphExecutionTests {
    @Test("Texture transforms convert source presentation metadata into sampling coordinates")
    func textureTransformConvertsPresentationMetadata() {
        let sourceSize = CGSize(width: 1920, height: 1080)
        let verticalFlip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceSize.height)

        let textureTransform = FabricImageTextureTransform.sourceToPresentation(verticalFlip,
                                                                                sourceSize: sourceSize)

        expectEqual(textureTransform, .textureVerticalFlip)

        let clockwiseQuarterTurn = CGAffineTransform(a: 0,
                                                     b: 1,
                                                     c: -1,
                                                     d: 0,
                                                     tx: sourceSize.height,
                                                     ty: 0)
        let rotatedTextureTransform = FabricImageTextureTransform.sourceToPresentation(clockwiseQuarterTurn,
                                                                                       sourceSize: sourceSize)
        let expectedRotatedTextureTransform = simd_float4x4(simd_float4(0, -1, 0, 0),
                                                            simd_float4(1, 0, 0, 0),
                                                            simd_float4(0, 0, 1, 0),
                                                            simd_float4(0, 1, 0, 1))
        expectEqual(rotatedTextureTransform, expectedRotatedTextureTransform)
    }

    @Test("Presentation CI images use the Fabric image transform")
    func presentationCIImageUsesTextureTransform() throws {
        guard let harness = GraphExecutionTestHarness(renderWidth: 4, renderHeight: 2) else { return }
        let rotatedImage = try harness.makeImage(width: 4, height: 2)
        rotatedImage.textureTransform = simd_float4x4(simd_float4(0, -1, 0, 0),
                                                      simd_float4(1, 0, 0, 0),
                                                      simd_float4(0, 0, 1, 0),
                                                      simd_float4(0, 1, 0, 1))
        #expect(rotatedImage.presentationCIImage?.extent == CGRect(x: 0, y: 0, width: 2, height: 4))
    }

    @Test("Transform-aware Base Image effects consume transforms into identity output")
    func transformAwareBaseImageEffectConsumesTransform() throws {
        guard let harness = GraphExecutionTestHarness(renderWidth: 4, renderHeight: 4) else { return }

        let shaderURL = FileManager.default.temporaryDirectory
            .appending(path: "Texture Transform Validation \(UUID().uuidString).metal")
        let shaderSource = """
        typedef struct {
            float unused;
        } PostUniforms;

        fragment half4 postFragment(
            VertexData in [[stage_in]],
            constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
            constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
            texture2d<half, access::sample> imageTexture [[texture(FragmentTextureCustom0)]])
        {
            constexpr sampler imageSampler(min_filter::nearest, mag_filter::nearest);
            const float2 imageUV = (imageTransforms[0] * float4(in.texcoord, 0.0, 1.0)).xy;
            return imageTexture.sample(imageSampler, imageUV);
        }
        """
        try shaderSource.write(to: shaderURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: shaderURL) }

        let node = try BaseImageNode(context: harness.context, fileURL: shaderURL)
        let input = try imagePort(named: "Image", kind: .Inlet, on: node)
        let output = try imagePort(named: "Image", kind: .Outlet, on: node)

        let image = try harness.makeImage(width: 4, height: 4)
        let red = [UInt8](repeating: 0, count: 4 * 2 * 4).enumerated().map { index, _ in
            [UInt8(0), 0, 255, 255][index % 4]
        }
        let blue = [UInt8](repeating: 0, count: 4 * 2 * 4).enumerated().map { index, _ in
            [UInt8(255), 0, 0, 255][index % 4]
        }
        let sourcePixels = red + blue
        sourcePixels.withUnsafeBytes { bytes in
            image.texture.replace(region: MTLRegionMake2D(0, 0, 4, 4),
                                  mipmapLevel: 0,
                                  withBytes: bytes.baseAddress!,
                                  bytesPerRow: 4 * 4)
        }
        image.textureTransform = .textureVerticalFlip

        let graph = Graph(context: harness.context)
        let imageMesh = ImageMeshNode(context: harness.context)
        graph.addNode(node)
        graph.addNode(imageMesh)
        graph.connect(output, to: imageMesh.inputImage)
        input.send(image, force: true)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph,
                           executionInfo: harness.makeExecutionInfo(),
                           drawScene: false)

        let outputImage = try #require(output.value)
        expectEqual(outputImage.textureTransform, matrix_identity_float4x4)
        #expect(outputImage.texture.width == 4)
        #expect(outputImage.texture.height == 4)

        let readbackDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                          width: 4,
                                                                          height: 4,
                                                                          mipmapped: false)
        readbackDescriptor.storageMode = .shared
        let readbackTexture = try #require(harness.context.device.makeTexture(descriptor: readbackDescriptor))
        let readbackCommandBuffer = try #require(harness.renderer.commandQueue.makeCommandBuffer())
        let blitEncoder = try #require(readbackCommandBuffer.makeBlitCommandEncoder())
        blitEncoder.copy(from: outputImage.texture,
                         sourceSlice: 0,
                         sourceLevel: 0,
                         sourceOrigin: .init(x: 0, y: 0, z: 0),
                         sourceSize: .init(width: 4, height: 4, depth: 1),
                         to: readbackTexture,
                         destinationSlice: 0,
                         destinationLevel: 0,
                         destinationOrigin: .init(x: 0, y: 0, z: 0))
        blitEncoder.endEncoding()
        readbackCommandBuffer.commit()
        readbackCommandBuffer.waitUntilCompleted()

        var outputPixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
        outputPixels.withUnsafeMutableBytes { bytes in
            readbackTexture.getBytes(bytes.baseAddress!,
                                     bytesPerRow: 4 * 4,
                                     from: MTLRegionMake2D(0, 0, 4, 4),
                                     mipmapLevel: 0)
        }
        #expect(Array(outputPixels[0..<4]) == [255, 0, 0, 255])
        #expect(Array(outputPixels[(3 * 4 * 4)..<(3 * 4 * 4 + 4)]) == [0, 0, 255, 255])

        let rotatedImage = try harness.makeImage(width: 4, height: 2)
        rotatedImage.textureTransform = simd_float4x4(simd_float4(0, -1, 0, 0),
                                                      simd_float4(1, 0, 0, 0),
                                                      simd_float4(0, 0, 1, 0),
                                                      simd_float4(0, 1, 0, 1))
        input.send(rotatedImage, force: true)
        try harness.render(graph: graph,
                           executionInfo: harness.makeExecutionInfo(frameNumber: 1),
                           drawScene: false)

        let rotatedOutputImage = try #require(output.value)
        expectEqual(rotatedOutputImage.textureTransform, matrix_identity_float4x4)
        #expect(rotatedOutputImage.texture.width == 2)
        #expect(rotatedOutputImage.texture.height == 4)

        try harness.renderer.stopExecution(graph: graph)
    }

    @Test("Multi-pass blur consumes input transforms into presentation-sized identity output")
    func multiPassBlurConsumesTransform() throws {
        guard let harness = GraphExecutionTestHarness(renderWidth: 2, renderHeight: 4) else { return }

        let image = try harness.makeImage(width: 4, height: 2)
        image.textureTransform = simd_float4x4(simd_float4(0, -1, 0, 0),
                                               simd_float4(1, 0, 0, 0),
                                               simd_float4(0, 0, 1, 0),
                                               simd_float4(0, 1, 0, 1))

        let blurNodes: [BaseImageNode] = [
            GaussianBlurNode(context: harness.context),
            GaussianBlurMaskNode(context: harness.context),
            GaussianBlurChannelsNode(context: harness.context),
            MotionBlurNode(context: harness.context),
            ZoomBlurNode(context: harness.context),
        ]

        for blurNode in blurNodes {
            let output = try imagePort(named: "Image", kind: .Outlet, on: blurNode)
            let graph = Graph(context: harness.context)
            let imageMesh = ImageMeshNode(context: harness.context)
            graph.addNode(blurNode)
            graph.addNode(imageMesh)
            graph.connect(output, to: imageMesh.inputImage)

            for input in blurNode.imageInputPorts() {
                input.send(image, force: true)
            }

            try harness.renderer.startExecution(graph: graph)
            try harness.render(graph: graph,
                               executionInfo: harness.makeExecutionInfo(),
                               drawScene: false)

            let outputImage = try #require(output.value)
            #expect(outputImage.texture.width == 2)
            #expect(outputImage.texture.height == 4)
            expectEqual(outputImage.textureTransform, matrix_identity_float4x4)

            try harness.renderer.stopExecution(graph: graph)
        }
    }

    @Test("Texture Crop uses presentation coordinates and returns identity output")
    func textureCropUsesPresentationCoordinates() throws {
        guard let harness = GraphExecutionTestHarness(renderWidth: 1, renderHeight: 4) else { return }

        let image = try harness.makeImage(width: 4, height: 2)
        let bluePixel: [UInt8] = [255, 0, 0, 255]
        let redPixel: [UInt8] = [0, 0, 255, 255]
        let sourcePixels = Array(repeating: bluePixel, count: 4).flatMap { $0 }
            + Array(repeating: redPixel, count: 4).flatMap { $0 }
        sourcePixels.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            image.texture.replace(region: MTLRegionMake2D(0, 0, 4, 2),
                                  mipmapLevel: 0,
                                  withBytes: baseAddress,
                                  bytesPerRow: 4 * 4)
        }
        image.textureTransform = simd_float4x4(simd_float4(0, -1, 0, 0),
                                               simd_float4(1, 0, 0, 0),
                                               simd_float4(0, 0, 1, 0),
                                               simd_float4(0, 1, 0, 1))

        let cropNode = TextureCropNode(context: harness.context)
        cropNode.inputCropX.value = 0
        cropNode.inputCropY.value = 0
        cropNode.inputCropWidth.value = 1
        cropNode.inputCropHeight.value = 4
        cropNode.inputTexture.send(image, force: true)

        let graph = Graph(context: harness.context)
        let imageMesh = ImageMeshNode(context: harness.context)
        graph.addNode(cropNode)
        graph.addNode(imageMesh)
        graph.connect(cropNode.outputTexture, to: imageMesh.inputImage)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: harness.makeExecutionInfo(), drawScene: false)

        let outputImage = try #require(cropNode.outputTexture.value)
        #expect(outputImage.texture.width == 1)
        #expect(outputImage.texture.height == 4)
        expectEqual(outputImage.textureTransform, matrix_identity_float4x4)

        let readbackDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                          width: 1,
                                                                          height: 4,
                                                                          mipmapped: false)
        readbackDescriptor.storageMode = .shared
        let readbackTexture = try #require(harness.context.device.makeTexture(descriptor: readbackDescriptor))
        let readbackCommandBuffer = try #require(harness.renderer.commandQueue.makeCommandBuffer())
        let blitEncoder = try #require(readbackCommandBuffer.makeBlitCommandEncoder())
        blitEncoder.copy(from: outputImage.texture,
                         sourceSlice: 0,
                         sourceLevel: 0,
                         sourceOrigin: .init(x: 0, y: 0, z: 0),
                         sourceSize: .init(width: 1, height: 4, depth: 1),
                         to: readbackTexture,
                         destinationSlice: 0,
                         destinationLevel: 0,
                         destinationOrigin: .init(x: 0, y: 0, z: 0))
        blitEncoder.endEncoding()
        readbackCommandBuffer.commit()
        readbackCommandBuffer.waitUntilCompleted()

        var outputPixels = [UInt8](repeating: 0, count: 1 * 4 * 4)
        outputPixels.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            readbackTexture.getBytes(baseAddress,
                                     bytesPerRow: 4,
                                     from: MTLRegionMake2D(0, 0, 1, 4),
                                     mipmapLevel: 0)
        }
        for row in 0..<4 {
            #expect(Array(outputPixels[(row * 4)..<(row * 4 + 4)]) == redPixel)
        }

        try harness.renderer.stopExecution(graph: graph)
    }

    @Test("Each Base Image input uses its own texture transform")
    func multiInputBaseImageEffectUsesIndependentTextureTransforms() throws {
        guard let harness = GraphExecutionTestHarness(renderWidth: 2, renderHeight: 2) else { return }

        let shaderURL = FileManager.default.temporaryDirectory
            .appending(path: "Multi Input Texture Transform Validation \(UUID().uuidString).metal")
        let shaderSource = """
        typedef struct {
            float unused;
        } PostUniforms;

        fragment half4 postFragment(
            VertexData in [[stage_in]],
            constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
            constant float4x4 *imageTransforms [[buffer(FragmentBufferCustom10)]],
            texture2d<half, access::sample> imageTexture0 [[texture(FragmentTextureCustom0)]],
            texture2d<half, access::sample> imageTexture1 [[texture(FragmentTextureCustom1)]])
        {
            constexpr sampler imageSampler(min_filter::nearest, mag_filter::nearest);
            const float2 imageUV0 = (imageTransforms[0] * float4(in.texcoord, 0.0, 1.0)).xy;
            const float2 imageUV1 = (imageTransforms[1] * float4(in.texcoord, 0.0, 1.0)).xy;
            const half4 color0 = imageTexture0.sample(imageSampler, imageUV0);
            const half4 color1 = imageTexture1.sample(imageSampler, imageUV1);
            return half4(color0.r, color1.g, 0.0h, 1.0h);
        }
        """
        try shaderSource.write(to: shaderURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: shaderURL) }

        let node = try BaseImageNode(context: harness.context, fileURL: shaderURL)
        let input0 = try imagePort(named: "Image", kind: .Inlet, on: node)
        let input1 = try imagePort(named: "Image 2", kind: .Inlet, on: node)
        let output = try imagePort(named: "Image", kind: .Outlet, on: node)

        let image0 = try harness.makeImage(width: 2, height: 2)
        let image1 = try harness.makeImage(width: 2, height: 2)
        let image0Pixels: [UInt8] = [
            0, 0, 255, 255, 0, 0, 255, 255,
            0, 0, 0, 255, 0, 0, 0, 255,
        ]
        let image1Pixels: [UInt8] = [
            0, 255, 0, 255, 0, 255, 0, 255,
            0, 0, 0, 255, 0, 0, 0, 255,
        ]
        image0Pixels.withUnsafeBytes { bytes in
            image0.texture.replace(region: MTLRegionMake2D(0, 0, 2, 2),
                                   mipmapLevel: 0,
                                   withBytes: bytes.baseAddress!,
                                   bytesPerRow: 2 * 4)
        }
        image1Pixels.withUnsafeBytes { bytes in
            image1.texture.replace(region: MTLRegionMake2D(0, 0, 2, 2),
                                   mipmapLevel: 0,
                                   withBytes: bytes.baseAddress!,
                                   bytesPerRow: 2 * 4)
        }
        image0.textureTransform = .textureVerticalFlip

        let graph = Graph(context: harness.context)
        let imageMesh = ImageMeshNode(context: harness.context)
        graph.addNode(node)
        graph.addNode(imageMesh)
        graph.connect(output, to: imageMesh.inputImage)
        input0.send(image0, force: true)
        input1.send(image1, force: true)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: harness.makeExecutionInfo(), drawScene: false)

        let outputImage = try #require(output.value)
        expectEqual(outputImage.textureTransform, matrix_identity_float4x4)

        let readbackDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                          width: 2,
                                                                          height: 2,
                                                                          mipmapped: false)
        readbackDescriptor.storageMode = .shared
        let readbackTexture = try #require(harness.context.device.makeTexture(descriptor: readbackDescriptor))
        let readbackCommandBuffer = try #require(harness.renderer.commandQueue.makeCommandBuffer())
        let blitEncoder = try #require(readbackCommandBuffer.makeBlitCommandEncoder())
        blitEncoder.copy(from: outputImage.texture,
                         sourceSlice: 0,
                         sourceLevel: 0,
                         sourceOrigin: .init(x: 0, y: 0, z: 0),
                         sourceSize: .init(width: 2, height: 2, depth: 1),
                         to: readbackTexture,
                         destinationSlice: 0,
                         destinationLevel: 0,
                         destinationOrigin: .init(x: 0, y: 0, z: 0))
        blitEncoder.endEncoding()
        readbackCommandBuffer.commit()
        readbackCommandBuffer.waitUntilCompleted()

        var outputPixels = [UInt8](repeating: 0, count: 2 * 2 * 4)
        outputPixels.withUnsafeMutableBytes { bytes in
            readbackTexture.getBytes(bytes.baseAddress!,
                                     bytesPerRow: 2 * 4,
                                     from: MTLRegionMake2D(0, 0, 2, 2),
                                     mipmapLevel: 0)
        }
        #expect(Array(outputPixels[0..<4]) == [0, 255, 0, 255])
        #expect(Array(outputPixels[(2 * 2 * 4 - 4)..<(2 * 2 * 4)]) == [0, 0, 255, 255])

        try harness.renderer.stopExecution(graph: graph)
    }

    @Test("Image Mesh uses Fabric image presentation dimensions and texture transform")
    func imageMeshUsesTextureTransform() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let node = ImageMeshNode(context: harness.context)
        let image = try harness.makeImage(width: 16, height: 8)
        #expect(image.presentationSize == CGSize(width: 16, height: 8))

        let clockwiseQuarterTurn = simd_float4x4(simd_float4(0, -1, 0, 0),
                                                 simd_float4(1, 0, 0, 0),
                                                 simd_float4(0, 0, 1, 0),
                                                 simd_float4(0, 1, 0, 1))
        image.textureTransform = clockwiseQuarterTurn
        #expect(image.presentationSize == CGSize(width: 8, height: 16))
        node.inputImage.value = image

        let graph = Graph(context: harness.context)
        graph.addNode(node)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph,
                           executionInfo: harness.makeExecutionInfo(),
                           drawScene: false)
        try harness.renderer.stopExecution(graph: graph)

        let mesh = try #require(node.getObject() as? Mesh)
        let material = try #require(mesh.material as? BasicTextureMaterial)
        let geometry = try #require(mesh.geometry as? PlaneGeometry)
        expectEqual(material.textureTransform, clockwiseQuarterTurn)
        #expect(abs(geometry.width - 1) <= 0.0001)
        #expect(abs(geometry.height - 2) <= 0.0001)
    }

    @Test("Material image inputs apply their Fabric image texture transforms")
    func materialImageInputsApplyTextureTransforms() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let quarterTurn = simd_float4x4(simd_float4(0, -1, 0, 0),
                                        simd_float4(1, 0, 0, 0),
                                        simd_float4(0, 0, 1, 0),
                                        simd_float4(0, 1, 0, 1))
        let flippedImage = try harness.makeImage(width: 4, height: 2)
        flippedImage.textureTransform = .textureVerticalFlip
        let rotatedImage = try harness.makeImage(width: 4, height: 2)
        rotatedImage.textureTransform = quarterTurn

        let standardNode = StandardMaterialNode(context: harness.context)
        standardNode.inputDiffuseTexture.send(flippedImage, force: true)
        standardNode.inputNormalTexture.send(rotatedImage, force: true)
        try harness.execute(standardNode)

        let baseColorTransform = try #require(standardNode.material.parameters.get(PBRTextureType.baseColor.texcoordName.titleCase,
                                                                                   as: Float4x4Parameter.self))
        let normalTransform = try #require(standardNode.material.parameters.get(PBRTextureType.normal.texcoordName.titleCase,
                                                                                as: Float4x4Parameter.self))
        expectEqual(baseColorTransform.value, .textureVerticalFlip)
        expectEqual(normalTransform.value, quarterTurn)

        let pbrNode = PBRMaterialNode(context: harness.context)
        pbrNode.inputBumpTexture.send(flippedImage, force: true)
        pbrNode.inputTransmissionTexture.send(rotatedImage, force: true)
        pbrNode.inputClearcoatRoughTexture.send(flippedImage, force: true)
        pbrNode.inputClearcoatGlossTexture.send(rotatedImage, force: true)
        try harness.execute(pbrNode)

        let bumpTransform = try #require(pbrNode.material.parameters.get(PBRTextureType.bump.texcoordName.titleCase,
                                                                         as: Float4x4Parameter.self))
        let transmissionTransform = try #require(pbrNode.material.parameters.get(PBRTextureType.transmission.texcoordName.titleCase,
                                                                                 as: Float4x4Parameter.self))
        let clearcoatSurfaceTransform = try #require(pbrNode.material.parameters.get(PBRTextureType.clearcoatRoughness.texcoordName.titleCase,
                                                                                    as: Float4x4Parameter.self))
        expectEqual(bumpTransform.value, .textureVerticalFlip)
        expectEqual(transmissionTransform.value, quarterTurn)
        expectEqual(clearcoatSurfaceTransform.value, .textureVerticalFlip)

        let displacementNode = DisplacementMaterialNode(context: harness.context)
        displacementNode.inputDisplacementTexture.send(flippedImage, force: true)
        displacementNode.inputTexture.send(rotatedImage, force: true)
        displacementNode.inputPointSpriteTexture.send(flippedImage, force: true)
        try harness.execute(displacementNode)

        let displacementTransform = try #require(displacementNode.material.parameters.get("displacementTextureTransform",
                                                                                           as: Float4x4Parameter.self))
        let colorTransform = try #require(displacementNode.material.parameters.get("colorTextureTransform",
                                                                                    as: Float4x4Parameter.self))
        let pointSpriteTransform = try #require(displacementNode.material.parameters.get("pointSpriteTextureTransform",
                                                                                          as: Float4x4Parameter.self))
        expectEqual(displacementTransform.value, .textureVerticalFlip)
        expectEqual(colorTransform.value, quarterTurn)
        expectEqual(pointSpriteTransform.value, .textureVerticalFlip)

        let graph = Graph(context: harness.context)
        let planeNode = PlaneGeometryNode(context: harness.context)
        let meshNode = MeshNode(context: harness.context)
        graph.addNode(planeNode)
        graph.addNode(displacementNode)
        graph.addNode(meshNode)
        graph.connect(planeNode.outputGeometry, to: meshNode.inputGeometry)
        graph.connect(displacementNode.outputMaterial, to: meshNode.inputMaterial)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: harness.makeExecutionInfo())
        try harness.renderer.stopExecution(graph: graph)
    }


    @Test("Number node outputs configured value after one render")
    func numberNodeOutputsConfiguredValue() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let numberNode = PassThroughNode<Float>(context: harness.context)
        numberNode.input.value = 3.5
        graph.addNode(numberNode)
        publish(numberNode.output, in: graph)

        let context = harness.makeExecutionContext(time: 10, deltaTime: 0, frameNumber: 0)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: context)
        try harness.renderer.stopExecution(graph: graph)

        try expectEqual(numberNode.output.value, 3.5)
    }

    @Test("Connected number nodes feed Number Binary Operator add")
    func connectedNumberNodesComputeSum() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let left = PassThroughNode<Float>(context: harness.context)
        let right = PassThroughNode<Float>(context: harness.context)
        let addNode = NumberBinaryOperator(context: harness.context)

        left.input.value = 2.25
        right.input.value = 4.75
        addNode.inputParam.value = "Add"

        graph.addNode(left)
        graph.addNode(right)
        graph.addNode(addNode)

        graph.connect(left.output, to: addNode.inputNumber1)
        graph.connect(right.output, to: addNode.inputNumber2)
        publish(addNode.outputNumber, in: graph)

        let context = harness.makeExecutionContext(time: 20, deltaTime: 0, frameNumber: 0)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: context)
        try harness.renderer.stopExecution(graph: graph)

        try expectEqual(addNode.outputNumber.value, 7.0)
    }

    @Test("Updating an upstream number recomputes the downstream output")
    func downstreamOutputUpdatesAfterInputChange() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let left = PassThroughNode<Float>(context: harness.context)
        let right = PassThroughNode<Float>(context: harness.context)
        let addNode = NumberBinaryOperator(context: harness.context)

        left.input.value = 1
        right.input.value = 2
        addNode.inputParam.value = "Add"

        graph.addNode(left)
        graph.addNode(right)
        graph.addNode(addNode)

        graph.connect(left.output, to: addNode.inputNumber1)
        graph.connect(right.output, to: addNode.inputNumber2)
        publish(addNode.outputNumber, in: graph)

        let firstContext = harness.makeExecutionContext(time: 30, deltaTime: 0, frameNumber: 0)
        let secondContext = harness.makeExecutionContext(time: 31, deltaTime: 1, frameNumber: 1)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: firstContext)
        try expectEqual(addNode.outputNumber.value, 3)

        right.input.value = 9
        try harness.render(graph: graph, executionInfo: secondContext)
        try harness.renderer.stopExecution(graph: graph)

        try expectEqual(addNode.outputNumber.value, 10)
    }

    @Test("Current time node advances relative to graph start")
    func currentTimeNodeUsesGraphTiming() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let timeNode = CurrentTimeNode(context: harness.context)
        graph.addNode(timeNode)
        publish(timeNode.outputNumber, in: graph)

        let firstContext = harness.makeExecutionContext(time: 0, deltaTime: 0, systemTime: 200, frameNumber: 0)
        let secondContext = harness.makeExecutionContext(time: 1.25, deltaTime: 1.25, systemTime: 201, frameNumber: 1)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: firstContext)
        try expectEqual(timeNode.outputNumber.value, 0)

        try harness.render(graph: graph, executionInfo: secondContext)
        try harness.renderer.stopExecution(graph: graph)

        try expectEqual(timeNode.outputNumber.value, 1.25)
    }

    @Test("System time node advances relative to execution start")
    func systemTimeNodeUsesSystemTiming() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let timeNode = SystemTimeNode(context: harness.context)
        graph.addNode(timeNode)
        publish(timeNode.outputNumber, in: graph)

        let firstContext = harness.makeExecutionContext(time: 100, deltaTime: 0, systemTime: 500, frameNumber: 0)
        let secondContext = harness.makeExecutionContext(time: 101, deltaTime: 1, systemTime: 502.5, frameNumber: 1)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: firstContext)
        try expectEqual(timeNode.outputNumber.value, 0)

        try harness.render(graph: graph, executionInfo: secondContext)
        try harness.renderer.stopExecution(graph: graph)

        try expectEqual(timeNode.outputNumber.value, 2.5)
    }

    @Test("Spot light node applies spotlight and shadow parameters")
    func spotLightNodeAppliesSpotlightAndShadowParameters() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let node = SpotLightNode(context: harness.context)
        node.inputColor.value = simd_float3(0.25, 0.5, 0.75)
        node.inputIntensity.value = 42.0
        node.inputRadius.value = 18.0
        node.inputAngleInner.value = 40.0
        node.inputAngleOuter.value = 30.0
        node.inputLookAt.value = simd_float3(0.0, -1.0, 0.0)
        node.inputShadowStrength.value = 1.5
        node.inputShadowRadius.value = 3.25
        node.inputShadowBias.value = 0.0025
        graph.addNode(node)

        let executionContext = harness.makeExecutionContext(time: 1.0, deltaTime: 0.0, frameNumber: 0)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: executionContext, drawScene: false)
        try harness.renderer.stopExecution(graph: graph)

        guard let light = node.getObject() as? SpotLight else {
            throw GraphExecutionTestFailure("Spot light node did not vend a SpotLight object")
        }

        expectEqual(light.color, simd_float3(0.25, 0.5, 0.75))
        #expect(abs(light.intensity - 42.0) <= 0.0001)
        #expect(abs(light.radius - 18.0) <= 0.0001)
        #expect(abs(light.angleInner - 40.0) <= 0.0001)
        #expect(abs(light.angleOuter - 40.0) <= 0.0001)
        #expect(abs(light.shadow.strength - 1.5) <= 0.0001)
        #expect(abs(light.shadow.radius - 3.25) <= 0.0001)
        #expect(abs(light.shadow.bias - 0.0025) <= 0.0001)
        #expect(light.castShadow)
    }

    @Test("Spot light node supports projector image texture transforms")
    func spotLightNodeSupportsProjectorImages() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let node = SpotLightNode(context: harness.context)
        node.inputProjectionMode.value = "Color"

        let texture = try harness.makeTexture(width: 16, height: 8)
        let image = FabricImage.unmanaged(texture: texture)
        image.textureTransform = .textureVerticalFlip
        node.inputProjectionImage.value = image
        graph.addNode(node)

        let executionContext = harness.makeExecutionContext(time: 2.0, deltaTime: 0.0, frameNumber: 0)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: executionContext, drawScene: false)
        try harness.renderer.stopExecution(graph: graph)

        guard let light = node.getObject() as? SpotLight else {
            throw GraphExecutionTestFailure("Spot light node did not vend a SpotLight object")
        }

        #expect(light.projectionTexture === texture)
        #expect(light.projectionMode == .color)

        let expectedFlipTransform = simd_float3x3(
            simd_float3(1.0, 0.0, 0.0),
            simd_float3(0.0, -1.0, 0.0),
            simd_float3(0.0, 1.0, 1.0)
        )
        expectEqual(light.projectionTransform, expectedFlipTransform)
    }

    @Test("Spot light node is registered in the node registry")
    func spotLightNodeIsRegistered() throws {
        let registry = try NodeRegistry.shared
        let nodeClass = registry.nodeClass(pluginID: PluginLoader.coreNodesPluginID,
                                           nodeID: String(describing: SpotLightNode.self))
        #expect(nodeClass == SpotLightNode.self)
    }

    @Test("Depth of field node renders an output image from color and depth inputs")
    func depthOfFieldNodeRendersOutputImage() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let node = DepthOfFieldNode(context: harness.context)
        node.inputImage.value = try harness.makeImage(width: 48, height: 32, pixelFormat: harness.context.colorPixelFormat)
        node.inputDepthImage.value = try harness.makeImage(width: 48, height: 32, pixelFormat: harness.context.depthPixelFormat)
        graph.addNode(node)
        publish(node.outputImage, in: graph)

        let executionContext = harness.makeExecutionContext(time: 0, deltaTime: 0, frameNumber: 0)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: executionContext, drawScene: false)
        try harness.renderer.stopExecution(graph: graph)

        let outputImage = try requireValue(node.outputImage.value, "Expected depth-of-field output image")
        #expect(outputImage.texture.width == 48)
        #expect(outputImage.texture.height == 32)
    }

    @Test("Post process motion blur node renders an output image from color and velocity inputs")
    func postProcessMotionBlurNodeRendersOutputImage() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let node = PostProcessMotionBlurNode(context: harness.context)
        node.inputImage.value = try harness.makeImage(width: 40, height: 24, pixelFormat: harness.context.colorPixelFormat)
        node.inputVelocityImage.value = try harness.makeImage(width: 40, height: 24, pixelFormat: harness.context.velocityPixelFormat)
        graph.addNode(node)
        publish(node.outputImage, in: graph)

        let executionContext = harness.makeExecutionContext(time: 0, deltaTime: 1.0 / 60.0, frameNumber: 0)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: executionContext, drawScene: false)
        try harness.renderer.stopExecution(graph: graph)

        let outputImage = try requireValue(node.outputImage.value, "Expected motion-blur output image")
        #expect(outputImage.texture.width == 40)
        #expect(outputImage.texture.height == 24)
    }

    @Test("Depth of field and post process motion blur nodes are registered in the node registry")
    func postProcessBlurNodesAreRegistered() throws {
        let availableNames = try Set(NodeRegistry.shared.availableNodes.map(\.nodeName))
        #expect(availableNames.contains(DepthOfFieldNode.name))
        #expect(availableNames.contains(PostProcessMotionBlurNode.name))
    }

    @Test("Render info reports renderer size and execution count")
    func renderInfoReportsMetrics() throws {
        guard let harness = GraphExecutionTestHarness(renderWidth: 640, renderHeight: 360) else { return }

        let graph = Graph(context: harness.context)
        let renderInfoNode = RenderInfoNode(context: harness.context)
        graph.addNode(renderInfoNode)
        publish(renderInfoNode.outputFrameNumber, in: graph)

        let firstContext = harness.makeExecutionContext(time: 200, deltaTime: 0, frameNumber: 0)
        let secondContext = harness.makeExecutionContext(time: 201, deltaTime: 1, frameNumber: 1)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: firstContext)

        try expectEqual(renderInfoNode.outputWidth.value, 640)
        try expectEqual(renderInfoNode.outputHeight.value, 360)
        #expect(renderInfoNode.outputFrameNumber.value == 0)

        try harness.render(graph: graph, executionInfo: secondContext)
        try harness.renderer.stopExecution(graph: graph)

        #expect(renderInfoNode.outputFrameNumber.value == 1)
    }

    @Test("Subgraph proxy inlet and outlet forward values across graphs")
    func subgraphProxyPortsForwardValues() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let source = PassThroughNode<Float>(context: harness.context)
        let subgraphNode = SubgraphNode(context: harness.context)
        let innerAdd = NumberBinaryOperator(context: harness.context)

        source.input.value = 4
        innerAdd.inputNumber2.value = 3
        innerAdd.inputParam.value = "Add"

        graph.addNode(source)
        graph.addNode(subgraphNode)

        subgraphNode.subGraph.addNode(innerAdd)
        innerAdd.inputNumber1.published = true
        innerAdd.outputNumber.published = true
        subgraphNode.subGraph.rebuildPublishedParameterGroup()

        let proxyInput = try floatPort(named: "Number A", kind: .Inlet, on: subgraphNode)
        let proxyOutput = try floatPort(named: "Number", kind: .Outlet, on: subgraphNode)

        graph.connect(source.output, to: proxyInput)
        publish(proxyOutput, in: graph)

        let context = harness.makeExecutionContext(time: 300, deltaTime: 0, frameNumber: 0)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: context)
        try harness.renderer.stopExecution(graph: graph)

        try expectEqual(innerAdd.inputNumber1.value, 4)
        try expectEqual(proxyOutput.value, 7)
    }

    @Test("Subgraph proxy preserves recursive array dictionary port type")
    func subgraphProxyPreservesRecursiveArrayDictionaryPortType() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let subgraphNode = SubgraphNode(context: harness.context)
        let innerNode = RecursiveArrayDictionaryPortNode(context: harness.context)

        subgraphNode.subGraph.addNode(innerNode)
        innerNode.port(named: "output").published = true
        subgraphNode.subGraph.rebuildPublishedParameterGroup()

        guard let proxyPort = subgraphNode.ports.first(where: { $0.name == "Recursive" && $0.kind == .Outlet }) else {
            throw GraphExecutionTestFailure("Missing recursive collection proxy port")
        }

        #expect(proxyPort.portType == RecursiveArrayDictionaryPortNode.recursivePortType)
    }

    @Test("Iterator node forwards the final iteration info state")
    func iteratorNodePublishesFinalIterationInfo() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let iterator = IteratorNode(context: harness.context)
        let iteratorInfo = IteratorInfoNode(context: harness.context)

        graph.addNode(iterator)
        iterator.subGraph.addNode(iteratorInfo)

        iterator.inputIteratonCount.value = 4

        iteratorInfo.outputIndex.published = true
        iteratorInfo.outputIterationCount.published = true
        iteratorInfo.outputProgress.published = true
        iterator.subGraph.rebuildPublishedParameterGroup()

        let indexProxy = try intPort(named: "Current Iteration", kind: .Outlet, on: iterator)
        let countProxy = try intPort(named: "Number of Iterations", kind: .Outlet, on: iterator)
        let progressProxy = try floatPort(named: "Iterator Progress", kind: .Outlet, on: iterator)

        publish(indexProxy, in: graph)

        let context = harness.makeExecutionContext(time: 400, deltaTime: 0, frameNumber: 0)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: context)
        try harness.renderer.stopExecution(graph: graph)

        #expect(indexProxy.value == 3)
        #expect(countProxy.value == 4)
        try expectEqual(progressProxy.value, 1)
    }

    @Test("Deferred subgraph renders color and depth images")
    func deferredSubgraphProducesImages() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let deferred = DeferredSubgraphNode(context: harness.context)

        deferred.inputWidth.value = 64
        deferred.inputHeight.value = 32

        let geometry = BoxGeometryNode(context: harness.context)
        let material = BasicColorMaterialNode(context: harness.context)
        let mesh = MeshNode(context: harness.context)

        deferred.subGraph.addNode(geometry)
        deferred.subGraph.addNode(material)
        deferred.subGraph.addNode(mesh)

        deferred.subGraph.connect(geometry.outputGeometry, to: mesh.inputGeometry)
        deferred.subGraph.connect(material.outputMaterial, to: mesh.inputMaterial)

        graph.addNode(deferred)

        let context = harness.makeExecutionContext(time: 500, deltaTime: 0, frameNumber: 0)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: context)
        try harness.renderer.stopExecution(graph: graph)

        let colorImage = try requireValue(deferred.outputColorTexture.value, "Expected deferred color output")
        #expect(colorImage.texture.width == 64)
        #expect(colorImage.texture.height == 32)

        let depthImage = try requireValue(deferred.outputDepthTexture.value, "Expected deferred depth output")
        #expect(depthImage.texture.width == 64)
        #expect(depthImage.texture.height == 32)
    }

    @Test("Deferred subgraph MRT toggle adds and removes auxiliary output ports")
    func deferredSubgraphMRTPortsToggleWithSetting() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let deferred = DeferredSubgraphNode(context: harness.context)
        #expect(deferred.findPort(named: "outputAlbedoTexture", as: Port.self) == nil)
        #expect(deferred.findPort(named: "outputEmissiveTexture", as: Port.self) == nil)

        deferred.deferredMRTEnabled = true

        _ = try imagePort(named: "Albedo Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "Normals Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "PBR Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "Velocity Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "Emissive Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "Color Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "Depth Texture", kind: .Outlet, on: deferred)

        deferred.deferredMRTEnabled = false

        #expect(deferred.findPort(named: "outputAlbedoTexture", as: Port.self) == nil)
        #expect(deferred.findPort(named: "outputNormalsTexture", as: Port.self) == nil)
        #expect(deferred.findPort(named: "outputPBRTexture", as: Port.self) == nil)
        #expect(deferred.findPort(named: "outputVelocityTexture", as: Port.self) == nil)
        #expect(deferred.findPort(named: "outputEmissiveTexture", as: Port.self) == nil)
        _ = try imagePort(named: "Color Texture", kind: .Outlet, on: deferred)
        _ = try imagePort(named: "Depth Texture", kind: .Outlet, on: deferred)
    }

    @Test("Deferred subgraph MRT mode emits auxiliary textures")
    func deferredSubgraphMRTProducesAuxiliaryTextures() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let deferred = DeferredSubgraphNode(context: harness.context)
        deferred.inputWidth.value = 72
        deferred.inputHeight.value = 40
        deferred.deferredMRTEnabled = true

        let geometry = BoxGeometryNode(context: harness.context)
        let material = StandardMaterialNode(context: harness.context)
        let mesh = MeshNode(context: harness.context)

        deferred.subGraph.addNode(geometry)
        deferred.subGraph.addNode(material)
        deferred.subGraph.addNode(mesh)

        deferred.subGraph.connect(geometry.outputGeometry, to: mesh.inputGeometry)
        deferred.subGraph.connect(material.outputMaterial, to: mesh.inputMaterial)

        graph.addNode(deferred)

        let context = harness.makeExecutionContext(time: 550, deltaTime: 0, frameNumber: 0)

        try harness.renderer.startExecution(graph: graph)
        try harness.render(graph: graph, executionInfo: context)
        try harness.renderer.stopExecution(graph: graph)

        let albedoImage = try requireValue(imagePort(named: "Albedo Texture", kind: .Outlet, on: deferred).value, "Expected deferred albedo output")
        let normalImage = try requireValue(imagePort(named: "Normals Texture", kind: .Outlet, on: deferred).value, "Expected deferred normals output")
        let pbrImage = try requireValue(imagePort(named: "PBR Texture", kind: .Outlet, on: deferred).value, "Expected deferred PBR output")
        let velocityImage = try requireValue(imagePort(named: "Velocity Texture", kind: .Outlet, on: deferred).value, "Expected deferred velocity output")
        let emissiveImage = try requireValue(imagePort(named: "Emissive Texture", kind: .Outlet, on: deferred).value, "Expected deferred emissive output")

        for image in [albedoImage, normalImage, pbrImage, velocityImage, emissiveImage] {
            #expect(image.texture.width == 72)
            #expect(image.texture.height == 40)
        }
    }

    @Test("Serialized scalar graph decodes and executes like the in-memory graph")
    func serializedScalarGraphRoundTripsAndExecutes() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let left = PassThroughNode<Float>(context: harness.context)
        let right = PassThroughNode<Float>(context: harness.context)
        let addNode = NumberBinaryOperator(context: harness.context)

        left.input.value = 8
        right.input.value = 13
        addNode.inputParam.value = "Add"

        graph.addNode(left)
        graph.addNode(right)
        graph.addNode(addNode)

        graph.connect(left.output, to: addNode.inputNumber1)
        graph.connect(right.output, to: addNode.inputNumber2)
        publish(addNode.outputNumber, in: graph)

        let decodedGraph = try roundTripGraphToTemporaryFile(graph, context: harness.context)

        #expect(decodedGraph.nodes.count == 3)

        guard let decodedAddNode = decodedGraph.nodes.compactMap({ $0 as? NumberBinaryOperator }).first else {
            throw GraphExecutionTestFailure("Expected decoded NumberBinaryOperator")
        }

        #expect(decodedAddNode.inputNumber1.connections.count == 1)
        #expect(decodedAddNode.inputNumber2.connections.count == 1)
        #expect(decodedAddNode.outputNumber.published)

        let context = harness.makeExecutionContext(time: 600, deltaTime: 0, frameNumber: 0)

        try harness.renderer.startExecution(graph: decodedGraph)
        try harness.render(graph: decodedGraph, executionInfo: context)
        try harness.renderer.stopExecution(graph: decodedGraph)

        try expectEqual(decodedAddNode.outputNumber.value, 21)
    }

    @Test("Serialized Transform pass-through preserves its identity parameter")
    func serializedTransformPassThroughPreservesIdentity() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let transformNode = PassThroughNode<simd_float4x4>(context: harness.context)

        graph.addNode(transformNode)
        publish(transformNode.output, in: graph)

        let decodedGraph = try roundTripGraphToTemporaryFile(graph, context: harness.context)

        guard let decodedTransformNode = decodedGraph.nodes.compactMap({
            $0 as? PassThroughNode<simd_float4x4>
        }).first else {
            throw GraphExecutionTestFailure("Expected decoded Transform pass-through node")
        }

        #expect(decodedTransformNode.input is ParameterPort<simd_float4x4>)
        #expect(decodedTransformNode.input.value == matrix_identity_float4x4)

        let context = harness.makeExecutionContext(time: 650, deltaTime: 0, frameNumber: 0)

        try harness.renderer.startExecution(graph: decodedGraph)
        try harness.render(graph: decodedGraph, executionInfo: context)
        try harness.renderer.stopExecution(graph: decodedGraph)

        #expect(decodedTransformNode.output.value == matrix_identity_float4x4)
    }

    @Test("Serialized subgraph preserves published proxies and decoded execution")
    func serializedSubgraphRoundTripsAndExecutes() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let source = PassThroughNode<Float>(context: harness.context)
        let subgraphNode = SubgraphNode(context: harness.context)
        let innerAdd = NumberBinaryOperator(context: harness.context)

        source.input.value = 5
        innerAdd.inputNumber2.value = 6
        innerAdd.inputParam.value = "Add"

        graph.addNode(source)
        graph.addNode(subgraphNode)

        subgraphNode.subGraph.addNode(innerAdd)
        innerAdd.inputNumber1.published = true
        innerAdd.outputNumber.published = true
        subgraphNode.subGraph.rebuildPublishedParameterGroup()

        let proxyInput = try floatPort(named: "Number A", kind: .Inlet, on: subgraphNode)
        let proxyOutput = try floatPort(named: "Number", kind: .Outlet, on: subgraphNode)

        graph.connect(source.output, to: proxyInput)
        publish(proxyOutput, in: graph)

        let decodedGraph = try roundTripGraphToTemporaryFile(graph, context: harness.context)

        guard let decodedSubgraph = decodedGraph.nodes.compactMap({ $0 as? SubgraphNode }).first else {
            throw GraphExecutionTestFailure("Expected decoded SubgraphNode")
        }

        let decodedProxyInput = try floatPort(named: "Number A", kind: .Inlet, on: decodedSubgraph)
        let decodedProxyOutput = try floatPort(named: "Number", kind: .Outlet, on: decodedSubgraph)

        #expect(decodedProxyInput.connections.count == 1)
        #expect(decodedProxyOutput.published)
        #expect(decodedSubgraph.subGraph.nodes.count == 1)

        let context = harness.makeExecutionContext(time: 700, deltaTime: 0, frameNumber: 0)

        try harness.renderer.startExecution(graph: decodedGraph)
        try harness.render(graph: decodedGraph, executionInfo: context)
        try harness.renderer.stopExecution(graph: decodedGraph)

        try expectEqual(decodedProxyOutput.value, 11)
    }

    @Test("Serialized nested subgraph binds proxy ports against the decoded inner graph")
    func serializedNestedSubgraphRoundTripsAndExecutes() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let source = PassThroughNode<Float>(context: harness.context)
        let outerSubgraph = SubgraphNode(context: harness.context)
        let innerSubgraph = SubgraphNode(context: harness.context)
        let innerAdd = NumberBinaryOperator(context: harness.context)

        source.input.value = 5
        innerAdd.inputNumber2.value = 7
        innerAdd.inputParam.value = "Add"

        graph.addNode(source)
        graph.addNode(outerSubgraph)

        innerSubgraph.subGraph.addNode(innerAdd)
        innerAdd.inputNumber1.published = true
        innerAdd.outputNumber.published = true
        innerSubgraph.subGraph.rebuildPublishedParameterGroup()

        let innerProxyInput = try floatPort(named: "Number A", kind: .Inlet, on: innerSubgraph)
        let innerProxyOutput = try floatPort(named: "Number", kind: .Outlet, on: innerSubgraph)
        innerProxyInput.published = true
        innerProxyOutput.published = true

        outerSubgraph.subGraph.addNode(innerSubgraph)
        outerSubgraph.subGraph.rebuildPublishedParameterGroup()

        let outerProxyInput = try floatPort(named: "Number A", kind: .Inlet, on: outerSubgraph)
        let outerProxyOutput = try floatPort(named: "Number", kind: .Outlet, on: outerSubgraph)

        graph.connect(source.output, to: outerProxyInput)
        publish(outerProxyOutput, in: graph)

        let decodedGraph = try roundTripGraphToTemporaryFile(graph, context: harness.context)

        guard let decodedOuterSubgraph = decodedGraph.nodes.compactMap({ $0 as? SubgraphNode }).first else {
            throw GraphExecutionTestFailure("Expected decoded outer SubgraphNode")
        }

        let decodedOuterProxyInput = try floatPort(named: "Number A", kind: .Inlet, on: decodedOuterSubgraph)
        let decodedOuterProxyOutput = try floatPort(named: "Number", kind: .Outlet, on: decodedOuterSubgraph)
        let decodedInnerSubgraph = try requireValue(
            decodedOuterSubgraph.subGraph.nodes.compactMap { $0 as? SubgraphNode }.first,
            "Expected decoded inner SubgraphNode"
        )
        let decodedInnerProxyInput = try floatPort(named: "Number A", kind: .Inlet, on: decodedInnerSubgraph)
        let decodedInnerProxyOutput = try floatPort(named: "Number", kind: .Outlet, on: decodedInnerSubgraph)

        #expect(decodedOuterProxyInput.connections.count == 1)
        #expect(decodedOuterProxyOutput.published)
        #expect(decodedInnerProxyInput.published)
        #expect(decodedInnerProxyOutput.published)
        #expect(decodedOuterProxyInput.id == decodedInnerProxyInput.id)
        #expect(decodedOuterProxyOutput.id == decodedInnerProxyOutput.id)

        let context = harness.makeExecutionContext(time: 750, deltaTime: 0, frameNumber: 0)

        try harness.renderer.startExecution(graph: decodedGraph)
        try harness.render(graph: decodedGraph, executionInfo: context)
        try harness.renderer.stopExecution(graph: decodedGraph)

        try expectEqual(decodedOuterProxyOutput.value, 12)
    }

    @Test("Serialized deferred subgraph still renders decoded outputs")
    func serializedDeferredSubgraphRoundTripsAndExecutes() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let deferred = DeferredSubgraphNode(context: harness.context)

        deferred.inputWidth.value = 48
        deferred.inputHeight.value = 24

        let geometry = BoxGeometryNode(context: harness.context)
        let material = BasicColorMaterialNode(context: harness.context)
        let mesh = MeshNode(context: harness.context)

        deferred.subGraph.addNode(geometry)
        deferred.subGraph.addNode(material)
        deferred.subGraph.addNode(mesh)

        deferred.subGraph.connect(geometry.outputGeometry, to: mesh.inputGeometry)
        deferred.subGraph.connect(material.outputMaterial, to: mesh.inputMaterial)

        graph.addNode(deferred)

        let decodedGraph = try roundTripGraphToTemporaryFile(graph, context: harness.context)

        guard let decodedDeferred = decodedGraph.nodes.compactMap({ $0 as? DeferredSubgraphNode }).first else {
            throw GraphExecutionTestFailure("Expected decoded DeferredSubgraphNode")
        }

        #expect(decodedDeferred.inputWidth.value == 48)
        #expect(decodedDeferred.inputHeight.value == 24)
        #expect(decodedDeferred.subGraph.nodes.compactMap { $0 as? MeshNode }.count == 1)

        let context = harness.makeExecutionContext(time: 800, deltaTime: 0, frameNumber: 0)

        try harness.renderer.startExecution(graph: decodedGraph)
        try harness.render(graph: decodedGraph, executionInfo: context)
        try harness.renderer.stopExecution(graph: decodedGraph)

        let colorImage = try requireValue(decodedDeferred.outputColorTexture.value, "Expected decoded deferred color output")
        #expect(colorImage.texture.width == 48)
        #expect(colorImage.texture.height == 24)

        let depthImage = try requireValue(decodedDeferred.outputDepthTexture.value, "Expected decoded deferred depth output")
        #expect(depthImage.texture.width == 48)
        #expect(depthImage.texture.height == 24)
    }

    @Test("Serialized deferred MRT subgraph restores auxiliary outputs and executes")
    func serializedDeferredMRTSubgraphRoundTripsAndExecutes() throws {
        guard let harness = GraphExecutionTestHarness() else { return }

        let graph = Graph(context: harness.context)
        let deferred = DeferredSubgraphNode(context: harness.context)
        deferred.inputWidth.value = 56
        deferred.inputHeight.value = 28
        deferred.deferredMRTEnabled = true

        let geometry = BoxGeometryNode(context: harness.context)
        let material = StandardMaterialNode(context: harness.context)
        let mesh = MeshNode(context: harness.context)

        deferred.subGraph.addNode(geometry)
        deferred.subGraph.addNode(material)
        deferred.subGraph.addNode(mesh)

        deferred.subGraph.connect(geometry.outputGeometry, to: mesh.inputGeometry)
        deferred.subGraph.connect(material.outputMaterial, to: mesh.inputMaterial)

        graph.addNode(deferred)

        let decodedGraph = try roundTripGraphToTemporaryFile(graph, context: harness.context)

        guard let decodedDeferred = decodedGraph.nodes.compactMap({ $0 as? DeferredSubgraphNode }).first else {
            throw GraphExecutionTestFailure("Expected decoded DeferredSubgraphNode")
        }

        #expect(decodedDeferred.deferredMRTEnabled)
        _ = try imagePort(named: "Albedo Texture", kind: .Outlet, on: decodedDeferred)
        _ = try imagePort(named: "Normals Texture", kind: .Outlet, on: decodedDeferred)
        _ = try imagePort(named: "PBR Texture", kind: .Outlet, on: decodedDeferred)
        _ = try imagePort(named: "Velocity Texture", kind: .Outlet, on: decodedDeferred)
        _ = try imagePort(named: "Emissive Texture", kind: .Outlet, on: decodedDeferred)

        let context = harness.makeExecutionContext(time: 850, deltaTime: 0, frameNumber: 0)

        try harness.renderer.startExecution(graph: decodedGraph)
        try harness.render(graph: decodedGraph, executionInfo: context)
        try harness.renderer.stopExecution(graph: decodedGraph)

        let albedoImage = try requireValue(imagePort(named: "Albedo Texture", kind: .Outlet, on: decodedDeferred).value, "Expected decoded deferred albedo output")
        let velocityImage = try requireValue(imagePort(named: "Velocity Texture", kind: .Outlet, on: decodedDeferred).value, "Expected decoded deferred velocity output")

        #expect(albedoImage.texture.width == 56)
        #expect(albedoImage.texture.height == 28)
        #expect(velocityImage.texture.width == 56)
        #expect(velocityImage.texture.height == 28)
    }
}
