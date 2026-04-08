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

    var colorPixelFormat: MTLPixelFormat {
        .bgra8Unorm
    }

    var ciFormat: CIFormat {
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
            pixelFormat: self.configuration.format.colorPixelFormat,
            width: self.configuration.size.width,
            height: self.configuration.size.height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]

        guard let texture = self.context.device.makeTexture(descriptor: descriptor) else {
            throw GraphImageExporterError.textureCreationFailed
        }

        let renderer = GraphExportRenderer(
            graph: self.graph,
            context: self.context,
            size: self.configuration.size,
            colorPixelFormat: self.configuration.format.colorPixelFormat
        )

        try renderer.renderSingleFrame(into: texture, time: self.configuration.time)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: texture.width,
            height: texture.height
        )

        guard let image = CIImage(mtlTexture: texture, options: [CIImageOption.colorSpace: colorSpace]),
              let cgImage = self.ciContext.createCGImage(
                image,
                from: bounds,
                format: self.configuration.format.ciFormat,
                colorSpace: colorSpace
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
}
