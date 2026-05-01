//
//  SVGNode.swift
//  Fabric
//
//  Render SVG markup directly to a texture image.
//  Parses all paths from the SVG and rasterizes them with
//  their embedded fill/stroke styles.
//

import Foundation
import Satin
import simd
import Metal
import CoreGraphics

public class SVGNode: Node
{
    public override class var name: String { "SVG" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .Generator) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Render SVG markup to a texture image" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputSVG", ParameterPort(parameter: StringParameter("SVG Markup", "", .inputfield, "SVG XML markup to render"))),
            ("inputWidth", ParameterPort(parameter: IntParameter("Width", 512, 1, 8192, .inputfield, "Output image width in pixels"))),
            ("inputHeight", ParameterPort(parameter: IntParameter("Height", 512, 1, 8192, .inputfield, "Output image height in pixels"))),

            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Rendered SVG image")),
        ]
    }

    public var inputSVG: ParameterPort<String> { port(named: "inputSVG") }
    public var inputWidth: ParameterPort<Int> { port(named: "inputWidth") }
    public var inputHeight: ParameterPort<Int> { port(named: "inputHeight") }
    public var outputTexturePort: NodePort<FabricImage> { port(named: "outputTexturePort") }

    @ObservationIgnored private var cachedSVGHash: Int?
    @ObservationIgnored private var cachedResult: SVGParseResult?
    @ObservationIgnored private var cachedCGPaths: [CGPath] = []

    public required init(context: Context)
    {
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let anyChanged = self.ports.contains(where: { $0.valueDidChange })
        guard anyChanged else { return }

        guard let svgString = inputSVG.value, !svgString.isEmpty else {
            outputTexturePort.send(nil)
            return
        }

        let width = max(1, inputWidth.value ?? 512)
        let height = max(1, inputHeight.value ?? 512)

        // Parse SVG (cached)
        let hash = svgString.hashValue
        let result: SVGParseResult
        let cgPaths: [CGPath]

        if hash == cachedSVGHash, let cached = cachedResult {
            result = cached
            cgPaths = cachedCGPaths
        } else {
            result = SVGParser.parse(svgString)
            var paths: [CGPath] = []
            for pathInfo in result.paths {
                if let cgPath = SVGPathConverter.pathFromSVGData(pathInfo.d) {
                    paths.append(cgPath)
                }
            }
            cgPaths = paths
            cachedSVGHash = hash
            cachedResult = result
            cachedCGPaths = paths
        }

        guard !cgPaths.isEmpty else {
            outputTexturePort.send(nil)
            return
        }

        // Build render operations from parsed SVG paths
        var operations: [SVGTextureRenderer.PathRenderOp] = []
        for (i, cgPath) in cgPaths.enumerated() {
            let pathInfo = result.paths[i]
            let hasFill = pathInfo.fillColor.w > 0
            let hasStroke = pathInfo.strokeColor.w > 0

            operations.append(SVGTextureRenderer.PathRenderOp(
                cgPath: cgPath,
                fillColor: pathInfo.fillColor,
                fillEnabled: hasFill,
                strokeColor: pathInfo.strokeColor,
                strokeEnabled: hasStroke,
                strokeWidth: pathInfo.strokeWidth
            ))
        }

        let device = context.graphRenderer!.context.device
        guard let image = SVGTextureRenderer.render(
            operations: operations,
            viewBox: result.viewBox,
            width: width, height: height,
            device: device
        ) else {
            outputTexturePort.send(nil)
            return
        }

        outputTexturePort.send(image)
    }
}
