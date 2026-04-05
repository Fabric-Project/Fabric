//
//  SVGImporterNode.swift
//  Fabric
//
//  Created by Claude on 3/28/26.
//

import Foundation
import Satin
import simd
import Metal

public class SVGImporterNode: Node
{
    public override class var name: String { "SVG Importer" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .Loader) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Parse SVG markup and extract path data, viewBox, and style by index" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            // Inputs
            ("inputSVG", ParameterPort(parameter: StringParameter("SVG Markup", "", .inputfield, "SVG XML markup to parse"))),
            ("inputPathIndex", ParameterPort(parameter: IntParameter("Path Index", 0, 0, 9999, .inputfield, "Index of the path element to output"))),

            // Outputs
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

    // MARK: - Cached parse result

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

        // Parse (or use cache)
        let hash = svgString.hashValue
        let result: SVGParseResult
        if hash == cachedSVGHash, let cached = cachedResult {
            result = cached
        } else {
            result = SVGImporterNode.parseSVG(svgString)
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

// MARK: - SVG Parser

private struct SVGPathInfo {
    let d: String
    let fillColor: simd_float4
    let strokeColor: simd_float4
    let strokeWidth: Float
}

private struct SVGParseResult {
    let viewBox: simd_float4      // x, y, w, h
    let paths: [SVGPathInfo]
}

extension SVGImporterNode {

    fileprivate static func parseSVG(_ svgString: String) -> SVGParseResult
    {
        guard let data = svgString.data(using: .utf8) else {
            return SVGParseResult(viewBox: .zero, paths: [])
        }

        let delegate = SVGParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        return SVGParseResult(viewBox: delegate.viewBox, paths: delegate.paths)
    }
}

// MARK: - XMLParser delegate

private class SVGParserDelegate: NSObject, XMLParserDelegate
{
    var viewBox: simd_float4 = simd_float4(0, 0, 100, 100)
    var paths: [SVGPathInfo] = []

    // Inherited style from <g> elements (simple single-level inheritance)
    private var groupFill: simd_float4?
    private var groupStroke: simd_float4?
    private var groupStrokeWidth: Float?

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String])
    {
        switch elementName.lowercased() {
        case "svg":
            if let vb = attributes["viewBox"] ?? attributes["viewbox"] {
                let parts = vb.split(whereSeparator: { $0 == " " || $0 == "," })
                    .compactMap { Float($0) }
                if parts.count == 4 {
                    viewBox = simd_float4(parts[0], parts[1], parts[2], parts[3])
                }
            } else if let w = attributes["width"].flatMap({ parseLength($0) }),
                      let h = attributes["height"].flatMap({ parseLength($0) }) {
                viewBox = simd_float4(0, 0, w, h)
            }

        case "g":
            if let fill = attributes["fill"] { groupFill = parseColor(fill) }
            if let stroke = attributes["stroke"] { groupStroke = parseColor(stroke) }
            if let sw = attributes["stroke-width"].flatMap({ Float($0) }) { groupStrokeWidth = sw }

        case "path":
            guard let d = attributes["d"], !d.isEmpty else { break }

            let fill = attributes["fill"].flatMap({ parseColor($0) })
                ?? groupFill
                ?? simd_float4(0, 0, 0, 1)     // SVG default fill is black
            let stroke = attributes["stroke"].flatMap({ parseColor($0) })
                ?? groupStroke
                ?? simd_float4(0, 0, 0, 0)     // SVG default stroke is none
            let strokeWidth = attributes["stroke-width"].flatMap({ Float($0) })
                ?? groupStrokeWidth
                ?? 1.0

            let isNoneFill = attributes["fill"]?.lowercased() == "none"

            paths.append(SVGPathInfo(
                d: d,
                fillColor: isNoneFill ? simd_float4(0, 0, 0, 0) : fill,
                strokeColor: stroke,
                strokeWidth: strokeWidth
            ))

        // Convert basic shapes to path d strings
        case "rect":
            if let d = rectToPath(attributes) {
                appendShapePath(d: d, attributes: attributes)
            }
        case "circle":
            if let d = circleToPath(attributes) {
                appendShapePath(d: d, attributes: attributes)
            }
        case "ellipse":
            if let d = ellipseToPath(attributes) {
                appendShapePath(d: d, attributes: attributes)
            }
        case "line":
            if let d = lineToPath(attributes) {
                appendShapePath(d: d, attributes: attributes)
            }
        case "polygon", "polyline":
            if let d = polyToPath(attributes, close: elementName.lowercased() == "polygon") {
                appendShapePath(d: d, attributes: attributes)
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?)
    {
        if elementName.lowercased() == "g" {
            groupFill = nil
            groupStroke = nil
            groupStrokeWidth = nil
        }
    }

    // MARK: - Shape to path converters

    private func appendShapePath(d: String, attributes: [String: String]) {
        let fill = attributes["fill"].flatMap({ parseColor($0) })
            ?? groupFill
            ?? simd_float4(0, 0, 0, 1)
        let stroke = attributes["stroke"].flatMap({ parseColor($0) })
            ?? groupStroke
            ?? simd_float4(0, 0, 0, 0)
        let strokeWidth = attributes["stroke-width"].flatMap({ Float($0) })
            ?? groupStrokeWidth
            ?? 1.0
        let isNoneFill = attributes["fill"]?.lowercased() == "none"

        paths.append(SVGPathInfo(
            d: d,
            fillColor: isNoneFill ? simd_float4(0, 0, 0, 0) : fill,
            strokeColor: stroke,
            strokeWidth: strokeWidth
        ))
    }

    private func rectToPath(_ attrs: [String: String]) -> String? {
        let x = attrs["x"].flatMap({ Float($0) }) ?? 0
        let y = attrs["y"].flatMap({ Float($0) }) ?? 0
        guard let w = attrs["width"].flatMap({ Float($0) }),
              let h = attrs["height"].flatMap({ Float($0) }) else { return nil }
        return "M \(x) \(y) L \(x+w) \(y) L \(x+w) \(y+h) L \(x) \(y+h) Z"
    }

    private func circleToPath(_ attrs: [String: String]) -> String? {
        guard let cx = attrs["cx"].flatMap({ Float($0) }),
              let cy = attrs["cy"].flatMap({ Float($0) }),
              let r = attrs["r"].flatMap({ Float($0) }) else { return nil }
        // Approximate circle with 4 cubic bezier arcs
        let k: Float = 0.5522848    // magic number for cubic bezier circle approximation
        let kr = k * r
        return "M \(cx) \(cy-r) "
            + "C \(cx+kr) \(cy-r) \(cx+r) \(cy-kr) \(cx+r) \(cy) "
            + "C \(cx+r) \(cy+kr) \(cx+kr) \(cy+r) \(cx) \(cy+r) "
            + "C \(cx-kr) \(cy+r) \(cx-r) \(cy+kr) \(cx-r) \(cy) "
            + "C \(cx-r) \(cy-kr) \(cx-kr) \(cy-r) \(cx) \(cy-r) Z"
    }

    private func ellipseToPath(_ attrs: [String: String]) -> String? {
        guard let cx = attrs["cx"].flatMap({ Float($0) }),
              let cy = attrs["cy"].flatMap({ Float($0) }),
              let rx = attrs["rx"].flatMap({ Float($0) }),
              let ry = attrs["ry"].flatMap({ Float($0) }) else { return nil }
        let kx = 0.5522848 * rx
        let ky = 0.5522848 * ry
        return "M \(cx) \(cy-ry) "
            + "C \(cx+kx) \(cy-ry) \(cx+rx) \(cy-ky) \(cx+rx) \(cy) "
            + "C \(cx+rx) \(cy+ky) \(cx+kx) \(cy+ry) \(cx) \(cy+ry) "
            + "C \(cx-kx) \(cy+ry) \(cx-rx) \(cy+ky) \(cx-rx) \(cy) "
            + "C \(cx-rx) \(cy-ky) \(cx-kx) \(cy-ry) \(cx) \(cy-ry) Z"
    }

    private func lineToPath(_ attrs: [String: String]) -> String? {
        guard let x1 = attrs["x1"].flatMap({ Float($0) }),
              let y1 = attrs["y1"].flatMap({ Float($0) }),
              let x2 = attrs["x2"].flatMap({ Float($0) }),
              let y2 = attrs["y2"].flatMap({ Float($0) }) else { return nil }
        return "M \(x1) \(y1) L \(x2) \(y2)"
    }

    private func polyToPath(_ attrs: [String: String], close: Bool) -> String? {
        guard let points = attrs["points"], !points.isEmpty else { return nil }
        let nums = points.split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap({ Float($0) })
        guard nums.count >= 4, nums.count % 2 == 0 else { return nil }
        var d = "M \(nums[0]) \(nums[1])"
        for i in stride(from: 2, to: nums.count, by: 2) {
            d += " L \(nums[i]) \(nums[i+1])"
        }
        if close { d += " Z" }
        return d
    }

    // MARK: - Color parsing

    private func parseLength(_ s: String) -> Float? {
        // Strip common units for basic support
        let stripped = s.replacingOccurrences(of: "px", with: "")
            .replacingOccurrences(of: "pt", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Float(stripped)
    }
}

// MARK: - SVG color string → simd_float4

private func parseColor(_ string: String) -> simd_float4?
{
    let s = string.trimmingCharacters(in: .whitespaces).lowercased()
    if s == "none" || s == "transparent" { return simd_float4(0, 0, 0, 0) }

    // #rgb or #rrggbb
    if s.hasPrefix("#") {
        let hex = String(s.dropFirst())
        if hex.count == 3 {
            let chars = Array(hex)
            let r = hexVal(chars[0]) * 17
            let g = hexVal(chars[1]) * 17
            let b = hexVal(chars[2]) * 17
            return simd_float4(Float(r) / 255, Float(g) / 255, Float(b) / 255, 1)
        } else if hex.count == 6 {
            let chars = Array(hex)
            let r = hexVal(chars[0]) * 16 + hexVal(chars[1])
            let g = hexVal(chars[2]) * 16 + hexVal(chars[3])
            let b = hexVal(chars[4]) * 16 + hexVal(chars[5])
            return simd_float4(Float(r) / 255, Float(g) / 255, Float(b) / 255, 1)
        }
    }

    // rgb(r, g, b)
    if s.hasPrefix("rgb("), s.hasSuffix(")") {
        let inner = s.dropFirst(4).dropLast(1)
        let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 3 {
            return simd_float4(parts[0] / 255, parts[1] / 255, parts[2] / 255, 1)
        }
    }

    // Named colors (common subset)
    switch s {
    case "black":   return simd_float4(0, 0, 0, 1)
    case "white":   return simd_float4(1, 1, 1, 1)
    case "red":     return simd_float4(1, 0, 0, 1)
    case "green":   return simd_float4(0, 0.502, 0, 1)
    case "blue":    return simd_float4(0, 0, 1, 1)
    case "yellow":  return simd_float4(1, 1, 0, 1)
    case "cyan":    return simd_float4(0, 1, 1, 1)
    case "magenta": return simd_float4(1, 0, 1, 1)
    case "orange":  return simd_float4(1, 0.647, 0, 1)
    case "gray", "grey": return simd_float4(0.502, 0.502, 0.502, 1)
    default:        return nil
    }
}

private func hexVal(_ c: Character) -> Int {
    switch c {
    case "0"..."9": return Int(c.asciiValue! - Character("0").asciiValue!)
    case "a"..."f": return 10 + Int(c.asciiValue! - Character("a").asciiValue!)
    default: return 0
    }
}
