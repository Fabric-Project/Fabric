//
//  GraphMovieExporter.swift
//  Fabric Editor
//
//  Created by Codex on 4/8/26.
//

import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import Metal
import Fabric
import Satin

enum GraphMovieExportCodec {
    case h264
    case hevc
    case proRes422
    case proRes4444

    var label: String {
        switch self {
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC"
        case .proRes422:
            return "ProRes 422"
        case .proRes4444:
            return "ProRes 4444"
        }
    }

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264:
            return .h264
        case .hevc:
            return .hevc
        case .proRes422:
            return .proRes422
        case .proRes4444:
            return .proRes4444
        }
    }
}

struct GraphMovieExportConfiguration {
    let url: URL
    let size: (width: Int, height: Int)
    let startTime: TimeInterval
    let duration: TimeInterval
    let frameRate: Double
    let codec: GraphMovieExportCodec
}

enum GraphMovieExporterError: Error {
    case invalidFrameRate
    case invalidDuration
    case invalidFrameCount
    case writerInputAppendFailed
    case missingPixelBufferPool
    case pixelBufferCreationFailed
    case textureCacheCreationFailed
    case textureCreationFailed
    case writerInputNotReady
    case assetWriterFailed(Error?)
}

final class GraphMovieExporter {
    private let graph: Graph
    private let context: Context
    private let configuration: GraphMovieExportConfiguration
    private let ciContext: CIContext

    init(graph: Graph, context: Context, configuration: GraphMovieExportConfiguration) {
        self.graph = graph
        self.context = context
        self.configuration = configuration
        self.ciContext = CIContext(mtlDevice: context.device)
    }

    func export() async throws {
        guard self.configuration.frameRate > 0 else {
            throw GraphMovieExporterError.invalidFrameRate
        }

        guard self.configuration.duration > 0 else {
            throw GraphMovieExporterError.invalidDuration
        }

        let frameCount = Int((self.configuration.duration * self.configuration.frameRate).rounded(.down))
        guard frameCount > 0 else {
            throw GraphMovieExporterError.invalidFrameCount
        }

        let writer = try AVAssetWriter(outputURL: self.configuration.url, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: self.configuration.codec.avCodec,
            AVVideoWidthKey: self.configuration.size.width,
            AVVideoHeightKey: self.configuration.size.height,
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: self.configuration.size.width,
            kCVPixelBufferHeightKey as String: self.configuration.size.height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw GraphMovieExporterError.assetWriterFailed(writer.error)
        }

        writer.add(writerInput)

        guard writer.startWriting() else {
            throw GraphMovieExporterError.assetWriterFailed(writer.error)
        }

        writer.startSession(atSourceTime: .zero)

        var textureCache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            self.context.device,
            nil,
            &textureCache
        )

        guard cacheStatus == kCVReturnSuccess, let textureCache else {
            throw GraphMovieExporterError.textureCacheCreationFailed
        }

        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            throw GraphMovieExporterError.missingPixelBufferPool
        }

        let renderer = GraphExportRenderer(
            graph: try self.makeExportGraphCopy(),
            context: self.context,
            size: self.configuration.size
        )

        let colorTexture = try self.makeIntermediateColorTexture()
        let depthTexture = try self.makeIntermediateDepthTexture()

        renderer.start()

        let frameDuration = self.frameDuration()
        let sourceColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: self.configuration.size.width,
            height: self.configuration.size.height
        )

        do {
            for frameIndex in 0 ..< frameCount {
                var pixelBuffer: CVPixelBuffer?
                let pixelBufferStatus = CVPixelBufferPoolCreatePixelBuffer(
                    kCFAllocatorDefault,
                    pixelBufferPool,
                    &pixelBuffer
                )

                guard pixelBufferStatus == kCVReturnSuccess, let pixelBuffer else {
                    throw GraphMovieExporterError.pixelBufferCreationFailed
                }

                var cvMetalTexture: CVMetalTexture?
                let textureStatus = CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault,
                    textureCache,
                    pixelBuffer,
                    nil,
                    .bgra8Unorm,
                    self.configuration.size.width,
                    self.configuration.size.height,
                    0,
                    &cvMetalTexture
                )

                guard textureStatus == kCVReturnSuccess,
                      let cvMetalTexture,
                      CVMetalTextureGetTexture(cvMetalTexture) != nil else {
                    throw GraphMovieExporterError.textureCreationFailed
                }

                let graphTime = self.configuration.startTime + (Double(frameIndex) / self.configuration.frameRate)
                try renderer.renderFrame(
                    into: colorTexture,
                    depthTexture: depthTexture,
                    time: graphTime
                )

                guard let image = CIImage(
                    mtlTexture: colorTexture,
                    options: [CIImageOption.colorSpace: sourceColorSpace]
                ) else {
                    throw GraphMovieExporterError.textureCreationFailed
                }

                let outputImage = self.orientedOutputImage(
                    from: image,
                    pixelBuffer: pixelBuffer
                )

                self.ciContext.render(
                    outputImage,
                    to: pixelBuffer,
                    bounds: bounds,
                    colorSpace: outputColorSpace
                )

                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                try await self.waitUntilReadyForMoreMediaData(writer: writer, writerInput: writerInput)
                guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    throw GraphMovieExporterError.writerInputAppendFailed
                }
            }
        } catch {
            renderer.finish()
            writerInput.markAsFinished()
            writer.cancelWriting()
            throw error
        }

        renderer.finish()
        writerInput.markAsFinished()

        if let completionError = try await self.finishWriting(writer) {
            throw GraphMovieExporterError.assetWriterFailed(completionError)
        }
    }

    private func makeExportGraphCopy() throws -> Graph {
        let encoder = JSONEncoder()
        let graphData = try encoder.encode(self.graph)

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: self.context)
        return try decoder.decode(Graph.self, from: graphData)
    }

    private func frameDuration() -> CMTime {
        switch self.configuration.frameRate {
        case 23.976:
            return CMTime(value: 1001, timescale: 24000)
        case 29.97:
            return CMTime(value: 1001, timescale: 30000)
        case 59.94:
            return CMTime(value: 1001, timescale: 60000)
        default:
            let preferredTimescale: CMTimeScale = 600_000
            let secondsPerFrame = 1.0 / self.configuration.frameRate
            let frameValue = Int64((secondsPerFrame * Double(preferredTimescale)).rounded())
            return CMTime(value: frameValue, timescale: preferredTimescale)
        }
    }

    private func makeIntermediateColorTexture() throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: self.context.colorPixelFormat,
            width: self.configuration.size.width,
            height: self.configuration.size.height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]

        guard let texture = self.context.device.makeTexture(descriptor: descriptor) else {
            throw GraphMovieExporterError.textureCreationFailed
        }

        return texture
    }

    private func makeIntermediateDepthTexture() throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: self.context.depthPixelFormat,
            width: self.configuration.size.width,
            height: self.configuration.size.height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget]

        guard let texture = self.context.device.makeTexture(descriptor: descriptor) else {
            throw GraphMovieExporterError.textureCreationFailed
        }

        return texture
    }

    private func finishWriting(_ writer: AVAssetWriter) async throws -> Error? {
        try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting {
                continuation.resume(returning: writer.error)
            }
        }
    }

    private func waitUntilReadyForMoreMediaData(
        writer: AVAssetWriter,
        writerInput: AVAssetWriterInput
    ) async throws {
        while !writerInput.isReadyForMoreMediaData {
            if writer.status == .failed || writer.status == .cancelled {
                throw GraphMovieExporterError.assetWriterFailed(writer.error)
            }

            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private func orientedOutputImage(from image: CIImage, pixelBuffer: CVPixelBuffer) -> CIImage {
        if self.pixelBufferIsFlipped(pixelBuffer) {
            return image
        }

        let imageExtent = image.extent
        let flipTransform = CGAffineTransform(translationX: 0, y: imageExtent.height)
            .scaledBy(x: 1, y: -1)

        return image.transformed(by: flipTransform)
    }

    private func pixelBufferIsFlipped(_ pixelBuffer: CVPixelBuffer) -> Bool {
        CVImageBufferIsFlipped(pixelBuffer)
    }
}
