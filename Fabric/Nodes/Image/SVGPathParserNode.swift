//
//  SVGPathParserNode.swift
//  Fabric
//
//  Parse SVG markup and extract path data, viewBox, and style by index.
//

import Foundation
import Satin
import simd
import Metal

public class SVGPathParserNode: Node
{
    public override class var name: String { "SVG Path Parser" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .Loader) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Parse SVG markup and extract path data, viewBox, and style by index" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputSVG", ParameterPort(parameter: StringParameter("SVG Markup", "", .inputfield, "SVG XML markup to parse"))),
            ("inputPathIndex", ParameterPort(parameter: IntParameter("Path Index", 0, 0, 9999, .inputfield, "Index of the path element to output"))),

            ("outputPathData", NodePort<String>(name: "Path Data", kind: .Outlet, description: "SVG path d attribute string")),
            ("outputPathCount", NodePort<Int>(name: "Path Count", kind: .Outlet, description: "Total number of paths found")),
            ("outputViewBoxX", NodePort<Float>(name: "ViewBox X", kind: .Outlet, description: "ViewBox origin X")),
            ("outputViewBoxY", NodePort<Float>(name: "ViewBox Y", kind: .Outlet, description: "ViewBox origin Y")),
            ("outputViewBoxW", NodePort<Float>(name: "ViewBox W", kind: .Outlet, description: "ViewBox width")),
            ("outputViewBoxH", NodePort<Float>(name: "ViewBox H", kind: .Outlet, description: "ViewBox height")),
            ("outputFillColor", NodePort<simd_float4>(name: "Fill Color", kind: .Outlet, description: "Fill color of selected path (RGBA)")),
            ("outputStrokeColor", NodePort<simd_float4>(name: "Stroke Color", kind: .Outlet, description: "Stroke color of selected path (RGBA)")),
            ("outputStrokeWidth", NodePort<Float>(name: "Stroke Width", kind: .Outlet, description: "Stroke width of selected path")),
        ]
    }

    public var inputSVG: ParameterPort<String> { port(named: "inputSVG") }
    public var inputPathIndex: ParameterPort<Int> { port(named: "inputPathIndex") }
    public var outputPathData: NodePort<String> { port(named: "outputPathData") }
    public var outputPathCount: NodePort<Int> { port(named: "outputPathCount") }
    public var outputViewBoxX: NodePort<Float> { port(named: "outputViewBoxX") }
    public var outputViewBoxY: NodePort<Float> { port(named: "outputViewBoxY") }
    public var outputViewBoxW: NodePort<Float> { port(named: "outputViewBoxW") }
    public var outputViewBoxH: NodePort<Float> { port(named: "outputViewBoxH") }
    public var outputFillColor: NodePort<simd_float4> { port(named: "outputFillColor") }
    public var outputStrokeColor: NodePort<simd_float4> { port(named: "outputStrokeColor") }
    public var outputStrokeWidth: NodePort<Float> { port(named: "outputStrokeWidth") }

    @ObservationIgnored private var cachedSVGHash: Int?
    @ObservationIgnored private var cachedResult: SVGParseResult?

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
        guard inputSVG.valueDidChange || inputPathIndex.valueDidChange else { return }

        guard let svgString = inputSVG.value, !svgString.isEmpty else {
            outputPathData.send(nil)
            outputPathCount.send(0)
            return
        }

        let hash = svgString.hashValue
        let result: SVGParseResult
        if hash == cachedSVGHash, let cached = cachedResult {
            result = cached
        } else {
            result = SVGParser.parse(svgString)
            cachedSVGHash = hash
            cachedResult = result
        }

        outputPathCount.send(result.paths.count)
        outputViewBoxX.send(result.viewBox.x)
        outputViewBoxY.send(result.viewBox.y)
        outputViewBoxW.send(result.viewBox.z)
        outputViewBoxH.send(result.viewBox.w)

        let index = inputPathIndex.value ?? 0
        guard !result.paths.isEmpty else {
            outputPathData.send(nil)
            outputFillColor.send(nil)
            outputStrokeColor.send(nil)
            outputStrokeWidth.send(nil)
            return
        }

        let clamped = max(0, min(index, result.paths.count - 1))
        let pathInfo = result.paths[clamped]

        outputPathData.send(pathInfo.d)
        outputFillColor.send(pathInfo.fillColor)
        outputStrokeColor.send(pathInfo.strokeColor)
        outputStrokeWidth.send(pathInfo.strokeWidth)
    }
}
