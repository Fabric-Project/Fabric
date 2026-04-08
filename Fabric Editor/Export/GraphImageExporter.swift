//
//  GraphImageExporter.swift
//  Fabric Editor
//
//  Created by Codex on 4/8/26.
//

import Foundation
import CoreImage
import ImageIO
import Metal
import UniformTypeIdentifiers
import Fabric
import Satin

enum GraphImageExportFormat {
    case png
    case jpeg(compressionQuality: CGFloat)
    case tiff

    var utType: UTType {
        switch self {
        case .png:
            return .png
        case .jpeg:
            return .jpeg
        case .tiff:
            return .tiff
        }
    }

    var encodedCIFormat: CIFormat {
        .BGRA8
    }
}

struct GraphImageExportConfiguration {
    let url: URL
    let size: (width: Int, height: Int)
    let time: TimeInterval
    let format: GraphImageExportFormat
}

enum GraphImageExporterError: Error {
    case textureCreationFailed
    case imageCreationFailed
    case imageDestinationCreationFailed
    case imageFinalizationFailed
}

final class GraphImageExporter {
    private let graph: Graph
    private let context: Context
    private let configuration: GraphImageExportConfiguration
    private let ciContext: CIContext

    init(graph: Graph, context: Context, configuration: GraphImageExportConfiguration) {
        self.graph = graph
        self.context = context
        self.configuration = configuration
        self.ciContext = CIContext(mtlDevice: context.device)
    }

    func export() throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: self.configuration.size.width,
            height: self.configuration.size.height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]

        guard let colorTexture = self.context.device.makeTexture(descriptor: descriptor) else {
            throw GraphImageExporterError.textureCreationFailed
        }

        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: self.context.depthPixelFormat,
            width: self.configuration.size.width,
            height: self.configuration.size.height,
            mipmapped: false
        )
        depthDescriptor.storageMode = .private
        depthDescriptor.usage = [.renderTarget]

        guard let depthTexture = self.context.device.makeTexture(descriptor: depthDescriptor) else {
            throw GraphImageExporterError.textureCreationFailed
        }

        let exportGraph = try self.makeExportGraphCopy()

        let renderer = GraphExportRenderer(
            graph: exportGraph,
            context: self.context,
            size: self.configuration.size
        )

        try renderer.renderSingleFrame(
            into: colorTexture,
            depthTexture: depthTexture,
            time: self.configuration.time
        )

        let sourceColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: colorTexture.width,
            height: colorTexture.height
        )

        guard let image = CIImage(
            mtlTexture: colorTexture,
            options: [CIImageOption.colorSpace: sourceColorSpace]
        ),
              let cgImage = self.ciContext.createCGImage(
                image,
                from: bounds,
                format: self.configuration.format.encodedCIFormat,
                colorSpace: outputColorSpace
              ) else {
            throw GraphImageExporterError.imageCreationFailed
        }

        guard let destination = CGImageDestinationCreateWithURL(
            self.configuration.url as CFURL,
            self.configuration.format.utType.identifier as CFString,
            1,
            nil
        ) else {
            throw GraphImageExporterError.imageDestinationCreationFailed
        }

        switch self.configuration.format {
        case .jpeg(let compressionQuality):
            CGImageDestinationAddImage(
                destination,
                cgImage,
                [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
            )
        case .png, .tiff:
            CGImageDestinationAddImage(destination, cgImage, nil)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GraphImageExporterError.imageFinalizationFailed
        }
    }

    private func makeExportGraphCopy() throws -> Graph {
        let encoder = JSONEncoder()
        let graphData = try encoder.encode(self.graph)

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: self.context)
        return try decoder.decode(Graph.self, from: graphData)
    }
}
