//
//  GraphMovieExporter.swift
//  Fabric Editor
//
//  Created by Codex on 4/8/26.
//

import Foundation
import AVFoundation
import CoreVideo
import Metal
import Fabric
import Satin

enum GraphMovieExportCodec {
    case h264
    case hevc
    case proRes422
    case proRes4444

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
    let frameRate: Int
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
    case assetWriterFailed(Error?)
}

final class GraphMovieExporter {
    private let graph: Graph
    private let context: Context
    private let configuration: GraphMovieExportConfiguration

    init(graph: Graph, context: Context, configuration: GraphMovieExportConfiguration) {
        self.graph = graph
        self.context = context
        self.configuration = configuration
    }

    func export() throws {
        guard self.configuration.frameRate > 0 else {
            throw GraphMovieExporterError.invalidFrameRate
        }

        guard self.configuration.duration > 0 else {
            throw GraphMovieExporterError.invalidDuration
        }

        let frameCount = Int((self.configuration.duration * Double(self.configuration.frameRate)).rounded(.down))
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
            graph: self.graph,
            context: self.context,
            size: self.configuration.size,
            colorPixelFormat: .bgra8Unorm
        )

        renderer.start()

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(self.configuration.frameRate))

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
                      let metalTexture = CVMetalTextureGetTexture(cvMetalTexture) else {
                    throw GraphMovieExporterError.textureCreationFailed
                }

                let graphTime = self.configuration.startTime + (Double(frameIndex) / Double(self.configuration.frameRate))
                try renderer.renderFrame(into: metalTexture, time: graphTime)

                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
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

        let semaphore = DispatchSemaphore(value: 0)
        var completionError: Error?

        writer.finishWriting {
            completionError = writer.error
            semaphore.signal()
        }

        semaphore.wait()

        if let completionError {
            throw GraphMovieExporterError.assetWriterFailed(completionError)
        }
    }
}
