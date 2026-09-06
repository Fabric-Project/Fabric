//
//  ANEInputBuffer.swift
//  Fabric
//

import CoreImage
import CoreVideo
import Foundation
import simd

/// Builds the IOSurface-backed CVPixelBuffer fed directly to
/// MLModel.prediction(from:) for RTMPose/RTMDet inference — replaces
/// Vision's VNImageRequestHandler/VNCoreMLRequest crop+scale path entirely.
/// Profiling showed -[VNImageRequestHandler performRequests:] consuming
/// ~43% of inference time on its own generic request-handling overhead
/// (format sniffing, orientation handling, multi-request coordination),
/// on top of the actual crop/scale cost. This does only the crop+scale,
/// via the same CIContext.render(_:to:bounds:) primitive Vision was
/// already using internally (confirmed in the same profile trace), with
/// none of Vision's surrounding machinery.
enum ANEInputBuffer
{
    private struct BufferCacheKey: Hashable
    {
        let width: Int
        let height: Int
    }

    // A fresh CVPixelBuffer per call meant a fresh IOSurface every frame,
    // which forced both CoreML's GPU backend and CIContext's renderer to
    // re-wrap that IOSurface in Metal resources every single call
    // (-[CaptureMTLDevice newBufferWithIOSurface:], newTextureWithDescriptor:
    // iosurface: — both showed up as real cost in profiling). Reusing the
    // same buffer per size lets both sides cache that wrapping instead.
    // Safe to share across model identities of the same size: execution is
    // synchronous and sequential (no concurrent node execution), and
    // CIContext.render(to: CVPixelBuffer) blocks until the GPU work
    // finishes, so the buffer's content is always fully written before
    // MLModel.prediction(from:) reads it.
    private static var pixelBufferCache: [BufferCacheKey: CVPixelBuffer] = [:]
    private static let cacheLock = NSLock()

    /// `regionOfInterest` is (x, y, width, height), normalized [0,1],
    /// bottom-left origin — Core Image's own coordinate convention, so no
    /// flip is needed converting it to a pixel-space crop rect.
    static func cropAndScale(image: FabricImage, regionOfInterest: simd_float4, destSize: CGSize, ciContext: CIContext) -> CVPixelBuffer?
    {
        guard let presentationImage = image.presentationCIImage else { return nil }
        guard let destinationBuffer = Self.pooledPixelBuffer(width: Int(destSize.width), height: Int(destSize.height)) else { return nil }

        let imageSize = image.presentationSize
        let cropRect = CGRect(
            x: CGFloat(regionOfInterest.x) * imageSize.width,
            y: CGFloat(regionOfInterest.y) * imageSize.height,
            width: CGFloat(regionOfInterest.z) * imageSize.width,
            height: CGFloat(regionOfInterest.w) * imageSize.height
        )

        guard cropRect.width > 0, cropRect.height > 0 else { return nil }

        let scaleX = destSize.width / cropRect.width
        let scaleY = destSize.height / cropRect.height
        // Translate the crop's origin to (0,0), then scale to the model's
        // exact input size, in one combined transform.
        let transform = CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y)
            .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))

        let transformedImage = presentationImage.cropped(to: cropRect).transformed(by: transform)
        let destinationBounds = CGRect(origin: .zero, size: destSize)

        ciContext.render(transformedImage, to: destinationBuffer, bounds: destinationBounds, colorSpace: nil)

        return destinationBuffer
    }

    private static func pooledPixelBuffer(width: Int, height: Int) -> CVPixelBuffer?
    {
        let key = BufferCacheKey(width: width, height: height)

        self.cacheLock.lock()
        defer { self.cacheLock.unlock() }

        if let cached = self.pixelBufferCache[key]
        {
            return cached
        }

        guard let buffer = Self.makePixelBuffer(width: width, height: height) else { return nil }
        self.pixelBufferCache[key] = buffer
        return buffer
    }

    private static func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer?
    {
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer)

        guard status == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }
}
