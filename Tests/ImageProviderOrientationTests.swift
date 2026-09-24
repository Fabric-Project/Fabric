import CoreImage
import ImageIO
import Metal
import Satin
import simd
import Testing
import UniformTypeIdentifiers
@testable import Fabric

@Suite("Image Provider Orientation")
struct ImageProviderOrientationTests
{
    @Test("Image Provider publishes file orientation and resets it on reload")
    func providerPublishesOrientation() throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bitmap = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80))
        let sourceImage = try #require(CIContext().createCGImage(bitmap, from: bitmap.extent))
        let node = ImageProviderNode(context: harness.context)

        for orientation in [6, 8, 2, 3, 4, 5, 7, 1]
        {
            let url = directory.appending(path: "orientation-\(orientation).tiff")
            let destination = try #require(CGImageDestinationCreateWithURL(
                url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, sourceImage,
                                       [kCGImagePropertyOrientation: orientation] as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))

            node.setFileURL(url)
            try harness.execute(node)
            let image = try #require(node.outputTexturePort.value)
            // Core Image is an independent reference here; the provider builds
            // its sampling matrix directly without allocating a CIImage.
            let referenceTransform = simd_float4x4.textureVerticalFlip
                * FabricImageTextureTransform.sourceToPresentation(
                    bitmap.orientationTransform(forExifOrientation: Int32(orientation)),
                    sourceSize: bitmap.extent.size)
                * .textureVerticalFlip
            for columnIndex in 0..<4
            {
                #expect(simd_distance(image.textureTransform[columnIndex],
                                      referenceTransform[columnIndex]) < 0.00001)
            }
            #expect(image.texture.width == 120)
            #expect(image.texture.height == 80)
            #expect(image.presentationSize == (orientation >= 5
                ? CGSize(width: 80, height: 120) : CGSize(width: 120, height: 80)))
            // Stored corners in presentation order: top-left, top-right,
            // bottom-left, bottom-right, including mirrored EXIF orientations.
            let corners: [SIMD2<Float>] = [[0, 0], [1, 0], [0, 1], [1, 1]]
            let expectedCornerIndices = [
                [0, 1, 2, 3], [1, 0, 3, 2], [3, 2, 1, 0], [2, 3, 0, 1],
                [0, 2, 1, 3], [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2],
            ]
            for (index, corner) in corners.enumerated()
            {
                let stored = image.textureTransform * SIMD4<Float>(corner.x, corner.y, 0, 1)
                let expected = corners[expectedCornerIndices[orientation - 1][index]]
                #expect(simd_distance(SIMD2<Float>(stored.x, stored.y), expected) < 0.00001)
            }
            if orientation == 1 {
                #expect(image.textureTransform == matrix_identity_float4x4)
            } else {
                #expect(image.textureTransform != matrix_identity_float4x4)
            }
        }
    }

}
