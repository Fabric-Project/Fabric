//
//  MTLTexture+Equatable.swift
//  Fabric
//
//  Created by Anton Marini on 5/5/25.
//
import Metal
import CoreImage
import CoreGraphics
import CoreVideo
import simd

public final class FabricImage: Identifiable, Equatable
{
    public let id = UUID()
    public let texture: MTLTexture

    /// Maps Fabric's canonical Satin UV coordinates into the coordinates
    /// required to sample the stored texture correctly.
    public var textureTransform: simd_float4x4 = matrix_identity_float4x4 {
        didSet {
            presentationSize = calculatePresentationSize()
        }
    }

    /// The image dimensions after applying its texture-coordinate transform.
    /// Unlike the texture dimensions, this reflects presentation orientation.
    public private(set) var presentationSize: CGSize

    private func calculatePresentationSize() -> CGSize {
        let transformedSize = simd_abs(textureTransform * simd_float4(Float(texture.width),
                                                                      Float(texture.height),
                                                                      0,
                                                                      0))
        return CGSize(width: CGFloat(transformedSize.x),
                      height: CGFloat(transformedSize.y))
    }

    // MARK: - Managed/unmanaged

    private var onRelease: ((MTLTexture) -> Void)?
    private var didRelease = false

    // Factory-only
    private init(texture: MTLTexture, onRelease: ((MTLTexture) -> Void)?)
    {
        self.texture = texture
        self.presentationSize = CGSize(width: texture.width, height: texture.height)
        self.onRelease = onRelease
    }

    /// Created by GraphRenderer (or other pool owner). Returned to pool on `release()` / `deinit`.
    internal static func managed(texture: MTLTexture, onRelease: @escaping (MTLTexture) -> Void) -> FabricImage
    {
        FabricImage(texture: texture, onRelease: onRelease)
    }

    /// Asset / external ownership. No pooling.
    public static func unmanaged(texture: MTLTexture) -> FabricImage
    {
        FabricImage(texture: texture, onRelease: nil)
    }

    deinit
    {
        release()
    }

    /// Optional explicit release for deterministic reuse (recommended in hot paths).
    public func release()
    {
        guard !didRelease else { return }
        didRelease = true
        onRelease?(texture)
        onRelease = nil
    }

    // MARK: - Equatable

    public static func == (lhs: FabricImage, rhs: FabricImage) -> Bool
    {
//        return lhs === rhs

        // 2) OR if you want texture identity:
        return lhs.texture === rhs.texture && lhs.id == rhs.id
    }

    /// Converts normalized coordinates in the stored texture back into
    /// Fabric's canonical texture-coordinate space.
    public func canonicalTextureCoordinate(fromStoredTextureCoordinate coordinate: simd_float2) -> simd_float2
    {
        let transformed = textureTransform.inverse * simd_float4(coordinate.x, coordinate.y, 0, 1)
        return simd_float2(transformed.x, transformed.y)
    }

    /// A Core Image view of the texture in Fabric's canonical presentation orientation.
    public var presentationCIImage: CIImage?
    {
        guard let storedImage = CIImage(mtlTexture: texture) else { return nil }

        let storedWidth = CGFloat(texture.width)
        let storedHeight = CGFloat(texture.height)
        let presentationWidth = presentationSize.width
        let presentationHeight = presentationSize.height

        func presentationPoint(fromStoredPoint point: CGPoint) -> CGPoint
        {
            let storedTextureCoordinate = simd_float4(Float(point.x / storedWidth),
                                                      1.0 - Float(point.y / storedHeight),
                                                      0,
                                                      1)

            let presentationTextureCoordinate = textureTransform.inverse * storedTextureCoordinate

            return CGPoint(x: CGFloat(presentationTextureCoordinate.x) * presentationWidth,
                           y: (1.0 - CGFloat(presentationTextureCoordinate.y)) * presentationHeight)
        }

        let origin = presentationPoint(fromStoredPoint: .zero)
        let horizontalPoint = presentationPoint(fromStoredPoint: CGPoint(x: 1, y: 0))
        let verticalPoint = presentationPoint(fromStoredPoint: CGPoint(x: 0, y: 1))
        let pixelTransform = CGAffineTransform(a: horizontalPoint.x - origin.x,
                                               b: horizontalPoint.y - origin.y,
                                               c: verticalPoint.x - origin.x,
                                               d: verticalPoint.y - origin.y,
                                               tx: origin.x,
                                               ty: origin.y)

        return storedImage
            .transformed(by: pixelTransform)
            .cropped(to: CGRect(origin: .zero, size: presentationSize))
    }
}

public enum FabricImageTextureTransform
{
    /// Converts Core Video's texture-origin convention into Fabric's
    /// canonical top-left Metal texture-coordinate convention.
    public static func coreVideo(_ pixelBuffer: CVPixelBuffer) -> simd_float4x4
    {
        CVImageBufferIsFlipped(pixelBuffer)
            ? matrix_identity_float4x4
            : .textureVerticalFlip
    }

    /// Converts an affine transform from source pixel coordinates into a
    /// normalized texture-coordinate sampling transform.
    ///
    /// `sourceToPresentationTransform` maps stored source pixels into their
    /// intended presentation. The returned matrix performs the inverse map:
    /// canonical presentation UV -> stored source UV.
    public static func sourceToPresentation(_ sourceToPresentationTransform: CGAffineTransform,
                                            sourceSize: CGSize) -> simd_float4x4
    {
        let sourceBounds = CGRect(origin: .zero, size: sourceSize)
        let presentationBounds = sourceBounds.applying(sourceToPresentationTransform).standardized
        let inverseTransform = sourceToPresentationTransform.inverted()

        func storedUV(presentationUV: CGPoint) -> simd_float2
        {
            let presentationPoint = CGPoint(x: presentationBounds.minX + presentationUV.x * presentationBounds.width,
                                            y: presentationBounds.minY + presentationUV.y * presentationBounds.height)
            let sourcePoint = presentationPoint.applying(inverseTransform)
            return simd_float2(Float(sourcePoint.x / sourceSize.width),
                               Float(sourcePoint.y / sourceSize.height))
        }

        let origin = storedUV(presentationUV: .zero)
        let horizontal = storedUV(presentationUV: CGPoint(x: 1, y: 0)) - origin
        let vertical = storedUV(presentationUV: CGPoint(x: 0, y: 1)) - origin

        return simd_float4x4(simd_float4(horizontal.x, horizontal.y, 0, 0),
                             simd_float4(vertical.x, vertical.y, 0, 0),
                             simd_float4(0, 0, 1, 0),
                             simd_float4(origin.x, origin.y, 0, 1))
    }

    /// Composes Core Video storage orientation with source presentation
    /// metadata such as an AVAssetTrack preferred transform.
    public static func video(pixelBuffer: CVPixelBuffer,
                             sourceToPresentationTransform: CGAffineTransform,
                             sourceSize: CGSize) -> simd_float4x4
    {
        coreVideo(pixelBuffer)
            * sourceToPresentation(sourceToPresentationTransform, sourceSize: sourceSize)
    }
}
