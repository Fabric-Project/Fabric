//
//  FabricGraphExportAutomation.swift
//  Fabric Editor
//
//  Created by Codex on 4/10/26.
//

import AppIntents
import Fabric
import Foundation

enum FabricImageExportFormatAppEnum: String, AppEnum {
    case png
    case jpeg
    case tiff

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fabric Image Export Format"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .png: "PNG",
        .jpeg: "JPEG",
        .tiff: "TIFF",
    ]

    var fileExtension: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpg"
        case .tiff:
            return "tiff"
        }
    }

    var graphFormat: GraphImageExportFormat {
        switch self {
        case .png:
            return .png
        case .jpeg:
            return .jpeg(compressionQuality: 0.9)
        case .tiff:
            return .tiff
        }
    }
}

enum FabricMovieExportCodecAppEnum: String, AppEnum {
    case h264
    case hevc
    case proRes422
    case proRes4444

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fabric Movie Export Codec"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .h264: "H.264",
        .hevc: "HEVC",
        .proRes422: "ProRes 422",
        .proRes4444: "ProRes 4444",
    ]

    var codec: GraphMovieExportCodec {
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

@MainActor
final class FabricGraphExportAutomation {
    static let shared = FabricGraphExportAutomation()

    static let defaultImageWidth = 1920
    static let defaultImageHeight = 1080
    static let defaultImageTime: TimeInterval = 0

    static let defaultMovieStartTime: TimeInterval = 0
    static let defaultMovieDuration: TimeInterval = 5
    static let defaultMovieWidth = 1920
    static let defaultMovieHeight = 1080
    static let defaultMovieFrameRate = 30.0

    private init() {}

    func exportImage(
        graph graphEntity: FabricGraphEntity,
        destinationPath: String,
        width: Int?,
        height: Int?,
        time: TimeInterval?,
        format: FabricImageExportFormatAppEnum
    ) throws -> IntentFile {
        let loadedGraph = try FabricDocumentAutomationService.shared.automationLoadedGraph(for: graphEntity)
        let size = try self.validatedImageSize(
            width: width ?? Self.defaultImageWidth,
            height: height ?? Self.defaultImageHeight
        )
        let destinationURL = try self.destinationURL(
            from: destinationPath,
            defaultExtension: format.fileExtension
        )
        try self.prepareDestinationURL(destinationURL)

        let configuration = GraphImageExportConfiguration(
            url: destinationURL,
            size: size,
            time: time ?? Self.defaultImageTime,
            format: format.graphFormat
        )
        let exporter = GraphImageExporter(
            graph: loadedGraph.graph,
            context: FabricDocumentAutomationService.shared.automationContext(),
            configuration: configuration
        )
        try exporter.export()

        return IntentFile(fileURL: destinationURL)
    }

    func exportMovie(
        graph graphEntity: FabricGraphEntity,
        destinationPath: String,
        startTime: TimeInterval?,
        duration: TimeInterval?,
        width: Int?,
        height: Int?,
        frameRate: Double?,
        codec: FabricMovieExportCodecAppEnum
    ) async throws -> IntentFile {
        let loadedGraph = try FabricDocumentAutomationService.shared.automationLoadedGraph(for: graphEntity)
        let size = try self.validatedMovieSize(
            width: width ?? Self.defaultMovieWidth,
            height: height ?? Self.defaultMovieHeight
        )
        let resolvedDuration = duration ?? Self.defaultMovieDuration
        let resolvedFrameRate = frameRate ?? Self.defaultMovieFrameRate

        guard resolvedDuration > 0 else {
            throw FabricIntentError.invalidValue("Duration must be greater than zero")
        }

        guard resolvedFrameRate > 0 else {
            throw FabricIntentError.invalidValue("Frame rate must be greater than zero")
        }

        let destinationURL = try self.destinationURL(from: destinationPath, defaultExtension: "mov")
        try self.prepareDestinationURL(destinationURL)

        let configuration = GraphMovieExportConfiguration(
            url: destinationURL,
            size: size,
            startTime: startTime ?? Self.defaultMovieStartTime,
            duration: resolvedDuration,
            frameRate: resolvedFrameRate,
            codec: codec.codec
        )
        let exporter = GraphMovieExporter(
            graph: loadedGraph.graph,
            context: FabricDocumentAutomationService.shared.automationContext(),
            configuration: configuration
        )

        do {
            try await exporter.export()
            return IntentFile(fileURL: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    private func validatedImageSize(width: Int, height: Int) throws -> (width: Int, height: Int) {
        guard width > 0, height > 0 else {
            throw FabricIntentError.invalidValue("Image width and height must be greater than zero")
        }

        return (width: width, height: height)
    }

    private func validatedMovieSize(width: Int, height: Int) throws -> (width: Int, height: Int) {
        guard width > 0, height > 0 else {
            throw FabricIntentError.invalidValue("Movie width and height must be greater than zero")
        }

        guard width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw FabricIntentError.invalidValue("Movie width and height must be even numbers")
        }

        return (width: width, height: height)
    }

    private func destinationURL(from destinationPath: String, defaultExtension: String) throws -> URL {
        let trimmedPath = destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw FabricIntentError.invalidValue("Destination path cannot be empty")
        }

        let resolvedURL: URL
        if let url = URL(string: trimmedPath), url.scheme != nil {
            guard url.isFileURL else {
                throw FabricIntentError.invalidValue("Destination must be a file URL")
            }
            resolvedURL = url.standardizedFileURL
        } else {
            resolvedURL = URL(fileURLWithPath: trimmedPath).standardizedFileURL
        }

        if resolvedURL.pathExtension.isEmpty {
            return resolvedURL.appendingPathExtension(defaultExtension)
        }

        return resolvedURL
    }

    private func prepareDestinationURL(_ url: URL) throws {
        let parentDirectory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: url.path) {
            throw FabricIntentError.fileAlreadyExists(url)
        }
    }
}
