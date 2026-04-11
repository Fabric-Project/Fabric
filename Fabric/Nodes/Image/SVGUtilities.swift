//
//  SVGUtilities.swift
//  Fabric
//
//  Shared SVG parsing, path conversion, and rendering utilities
//  used by SVGPathParserNode, SVGPathRendererNode, and SVGNode.
//

import Foundation
import Satin
import CoreGraphics
import Metal
import simd

// MARK: - SVG Parse Types

struct SVGPathInfo {
    let d: String
    let fillColor: simd_float4
    let strokeColor: simd_float4
    let strokeWidth: Float
}

struct SVGParseResult {
    let viewBox: simd_float4      // x, y, w, h
    let paths: [SVGPathInfo]
}

// MARK: - SVG XML Parser

enum SVGParser {

    static func parse(_ svgString: String) -> SVGParseResult {
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

// MARK: - XMLParser Delegate

private class SVGParserDelegate: NSObject, XMLParserDelegate {

    var viewBox: simd_float4 = simd_float4(0, 0, 100, 100)
    var paths: [SVGPathInfo] = []

    // CSS class definitions from <style> blocks
    private var classStyles: [String: [String: String]] = [:]
    private var isInsideStyleElement = false
    private var styleContent = ""

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
        case "style":
            isInsideStyleElement = true
            styleContent = ""

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
            let gStyle = resolvedStyles(for: attributes)
            if let fill = gStyle["fill"] { groupFill = parseSVGColor(fill) }
            if let stroke = gStyle["stroke"] { groupStroke = parseSVGColor(stroke) }
            if let sw = gStyle["stroke-width"].flatMap({ Float($0) }) { groupStrokeWidth = sw }

        case "path":
            guard let d = attributes["d"], !d.isEmpty else { break }
            appendShapePath(d: d, attributes: attributes)

        case "rect":
            if let d = rectToPath(attributes) { appendShapePath(d: d, attributes: attributes) }
        case "circle":
            if let d = circleToPath(attributes) { appendShapePath(d: d, attributes: attributes) }
        case "ellipse":
            if let d = ellipseToPath(attributes) { appendShapePath(d: d, attributes: attributes) }
        case "line":
            if let d = lineToPath(attributes) { appendShapePath(d: d, attributes: attributes) }
        case "polygon", "polyline":
            if let d = polyToPath(attributes, close: elementName.lowercased() == "polygon") {
                appendShapePath(d: d, attributes: attributes)
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideStyleElement {
            styleContent += string
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?)
    {
        switch elementName.lowercased() {
        case "g":
            groupFill = nil
            groupStroke = nil
            groupStrokeWidth = nil
        case "style":
            isInsideStyleElement = false
            parseCSSBlock(styleContent)
        default:
            break
        }
    }

    /// Parse a CSS block like `.cls-1 { fill: #7f0196; }` into classStyles dictionary.
    private func parseCSSBlock(_ css: String) {
        // Match patterns like: .className { property: value; ... }
        var i = css.startIndex
        while i < css.endIndex {
            // Find '.'
            guard let dotIdx = css[i...].firstIndex(of: ".") else { break }
            // Find '{'
            guard let braceOpen = css[dotIdx...].firstIndex(of: "{") else { break }
            // Find '}'
            guard let braceClose = css[braceOpen...].firstIndex(of: "}") else { break }

            let className = css[css.index(after: dotIdx)..<braceOpen]
                .trimmingCharacters(in: .whitespaces)
            let body = css[css.index(after: braceOpen)..<braceClose]

            var props: [String: String] = [:]
            for declaration in body.split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    props[key] = value
                }
            }

            if !className.isEmpty {
                classStyles[className] = props
            }

            i = css.index(after: braceClose)
        }
    }

    // MARK: - Style parsing

    /// Parse a CSS `style` attribute into a dictionary of property→value pairs.
    /// e.g. "fill:#ff0000;stroke:none;stroke-width:2" → ["fill":"#ff0000", "stroke":"none", "stroke-width":"2"]
    private func parseStyleAttribute(_ style: String) -> [String: String] {
        var result: [String: String] = [:]
        for declaration in style.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }

    private func resolveColor(style: [String: String],
                              property: String, groupValue: simd_float4?) -> (value: simd_float4?, isNone: Bool) {
        if let raw = style[property] {
            if raw.lowercased() == "none" { return (nil, true) }
            if let color = parseSVGColor(raw) { return (color, false) }
        }
        return (groupValue, false)
    }

    // MARK: - Helpers

    private func resolvedStyles(for attributes: [String: String]) -> [String: String] {
        var merged: [String: String] = [:]

        // 1. CSS class properties (lowest priority after group)
        if let className = attributes["class"] {
            for cls in className.split(separator: " ") {
                if let classProps = classStyles[String(cls)] {
                    merged.merge(classProps) { _, new in new }
                }
            }
        }

        // 2. Presentation attributes
        for key in ["fill", "stroke", "stroke-width", "opacity", "fill-opacity"] {
            if let val = attributes[key] { merged[key] = val }
        }

        // 3. Inline style (highest priority)
        if let style = attributes["style"] {
            merged.merge(parseStyleAttribute(style)) { _, new in new }
        }

        return merged
    }

    private func appendShapePath(d: String, attributes: [String: String]) {
        let style = resolvedStyles(for: attributes)

        let (resolvedFill, isNoneFill) = resolveColor(style: style,
                                                       property: "fill", groupValue: groupFill)
        let fill = resolvedFill ?? simd_float4(0, 0, 0, 1)   // SVG default fill is black

        let (resolvedStroke, _) = resolveColor(style: style,
                                                property: "stroke", groupValue: groupStroke)
        let stroke = resolvedStroke ?? simd_float4(0, 0, 0, 0) // SVG default stroke is none

        let strokeWidth = style["stroke-width"].flatMap({ Float($0) })
            ?? groupStrokeWidth
            ?? 1.0

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
        let k: Float = 0.5522848
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

    private func parseLength(_ s: String) -> Float? {
        let stripped = s.replacingOccurrences(of: "px", with: "")
            .replacingOccurrences(of: "pt", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Float(stripped)
    }
}

// MARK: - SVG Color Parsing

func parseSVGColor(_ string: String) -> simd_float4? {
    let s = string.trimmingCharacters(in: .whitespaces).lowercased()
    if s == "none" || s == "transparent" { return simd_float4(0, 0, 0, 0) }

    if s.hasPrefix("#") {
        let hex = String(s.dropFirst())
        if hex.count == 3 {
            let chars = Array(hex)
            let r = svgHexVal(chars[0]) * 17
            let g = svgHexVal(chars[1]) * 17
            let b = svgHexVal(chars[2]) * 17
            return simd_float4(Float(r) / 255, Float(g) / 255, Float(b) / 255, 1)
        } else if hex.count == 6 {
            let chars = Array(hex)
            let r = svgHexVal(chars[0]) * 16 + svgHexVal(chars[1])
            let g = svgHexVal(chars[2]) * 16 + svgHexVal(chars[3])
            let b = svgHexVal(chars[4]) * 16 + svgHexVal(chars[5])
            return simd_float4(Float(r) / 255, Float(g) / 255, Float(b) / 255, 1)
        }
    }

    if s.hasPrefix("rgb("), s.hasSuffix(")") {
        let inner = s.dropFirst(4).dropLast(1)
        let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 3 {
            return simd_float4(parts[0] / 255, parts[1] / 255, parts[2] / 255, 1)
        }
    }

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

private func svgHexVal(_ c: Character) -> Int {
    switch c {
    case "0"..."9": return Int(c.asciiValue! - Character("0").asciiValue!)
    case "a"..."f": return 10 + Int(c.asciiValue! - Character("a").asciiValue!)
    default: return 0
    }
}

// MARK: - SVG Path d String → CGPath

enum SVGPathConverter {

    static func pathFromSVGData(_ d: String) -> CGPath? {
        let path = CGMutablePath()
        let tokens = tokenize(d)
        var i = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lastControlX: CGFloat = 0
        var lastControlY: CGFloat = 0
        var lastCommand: Character = " "
        var subpathStartX: CGFloat = 0
        var subpathStartY: CGFloat = 0

        func nextFloat() -> CGFloat? {
            guard i < tokens.count, let v = Double(tokens[i]) else { return nil }
            i += 1
            return CGFloat(v)
        }

        while i < tokens.count {
            let token = tokens[i]

            let cmd: Character
            if let first = token.first, (first.isNumber || first == "-" || first == "+" || first == ".") {
                if lastCommand == "M" { cmd = "L" }
                else if lastCommand == "m" { cmd = "l" }
                else { cmd = lastCommand }
            } else {
                cmd = Character(token)
                i += 1
            }

            switch cmd {
            case "M":
                guard let x = nextFloat(), let y = nextFloat() else { break }
                path.move(to: CGPoint(x: x, y: y))
                currentX = x; currentY = y
                subpathStartX = x; subpathStartY = y
                lastControlX = x; lastControlY = y

            case "m":
                guard let dx = nextFloat(), let dy = nextFloat() else { break }
                let x = currentX + dx, y = currentY + dy
                path.move(to: CGPoint(x: x, y: y))
                currentX = x; currentY = y
                subpathStartX = x; subpathStartY = y
                lastControlX = x; lastControlY = y

            case "L":
                guard let x = nextFloat(), let y = nextFloat() else { break }
                path.addLine(to: CGPoint(x: x, y: y))
                currentX = x; currentY = y
                lastControlX = x; lastControlY = y

            case "l":
                guard let dx = nextFloat(), let dy = nextFloat() else { break }
                let x = currentX + dx, y = currentY + dy
                path.addLine(to: CGPoint(x: x, y: y))
                currentX = x; currentY = y
                lastControlX = x; lastControlY = y

            case "H":
                guard let x = nextFloat() else { break }
                path.addLine(to: CGPoint(x: x, y: currentY))
                currentX = x
                lastControlX = currentX; lastControlY = currentY

            case "h":
                guard let dx = nextFloat() else { break }
                currentX += dx
                path.addLine(to: CGPoint(x: currentX, y: currentY))
                lastControlX = currentX; lastControlY = currentY

            case "V":
                guard let y = nextFloat() else { break }
                path.addLine(to: CGPoint(x: currentX, y: y))
                currentY = y
                lastControlX = currentX; lastControlY = currentY

            case "v":
                guard let dy = nextFloat() else { break }
                currentY += dy
                path.addLine(to: CGPoint(x: currentX, y: currentY))
                lastControlX = currentX; lastControlY = currentY

            case "C":
                guard let x1 = nextFloat(), let y1 = nextFloat(),
                      let x2 = nextFloat(), let y2 = nextFloat(),
                      let x = nextFloat(), let y = nextFloat() else { break }
                path.addCurve(to: CGPoint(x: x, y: y),
                              control1: CGPoint(x: x1, y: y1),
                              control2: CGPoint(x: x2, y: y2))
                lastControlX = x2; lastControlY = y2
                currentX = x; currentY = y

            case "c":
                guard let dx1 = nextFloat(), let dy1 = nextFloat(),
                      let dx2 = nextFloat(), let dy2 = nextFloat(),
                      let dx = nextFloat(), let dy = nextFloat() else { break }
                let x1 = currentX + dx1, y1 = currentY + dy1
                let x2 = currentX + dx2, y2 = currentY + dy2
                let x = currentX + dx, y = currentY + dy
                path.addCurve(to: CGPoint(x: x, y: y),
                              control1: CGPoint(x: x1, y: y1),
                              control2: CGPoint(x: x2, y: y2))
                lastControlX = x2; lastControlY = y2
                currentX = x; currentY = y

            case "S":
                guard let x2 = nextFloat(), let y2 = nextFloat(),
                      let x = nextFloat(), let y = nextFloat() else { break }
                let rx = 2 * currentX - lastControlX
                let ry = 2 * currentY - lastControlY
                path.addCurve(to: CGPoint(x: x, y: y),
                              control1: CGPoint(x: rx, y: ry),
                              control2: CGPoint(x: x2, y: y2))
                lastControlX = x2; lastControlY = y2
                currentX = x; currentY = y

            case "s":
                guard let dx2 = nextFloat(), let dy2 = nextFloat(),
                      let dx = nextFloat(), let dy = nextFloat() else { break }
                let rx = 2 * currentX - lastControlX
                let ry = 2 * currentY - lastControlY
                let x2 = currentX + dx2, y2 = currentY + dy2
                let x = currentX + dx, y = currentY + dy
                path.addCurve(to: CGPoint(x: x, y: y),
                              control1: CGPoint(x: rx, y: ry),
                              control2: CGPoint(x: x2, y: y2))
                lastControlX = x2; lastControlY = y2
                currentX = x; currentY = y

            case "Q":
                guard let x1 = nextFloat(), let y1 = nextFloat(),
                      let x = nextFloat(), let y = nextFloat() else { break }
                path.addQuadCurve(to: CGPoint(x: x, y: y),
                                  control: CGPoint(x: x1, y: y1))
                lastControlX = x1; lastControlY = y1
                currentX = x; currentY = y

            case "q":
                guard let dx1 = nextFloat(), let dy1 = nextFloat(),
                      let dx = nextFloat(), let dy = nextFloat() else { break }
                let x1 = currentX + dx1, y1 = currentY + dy1
                let x = currentX + dx, y = currentY + dy
                path.addQuadCurve(to: CGPoint(x: x, y: y),
                                  control: CGPoint(x: x1, y: y1))
                lastControlX = x1; lastControlY = y1
                currentX = x; currentY = y

            case "T":
                guard let x = nextFloat(), let y = nextFloat() else { break }
                let rx = 2 * currentX - lastControlX
                let ry = 2 * currentY - lastControlY
                path.addQuadCurve(to: CGPoint(x: x, y: y),
                                  control: CGPoint(x: rx, y: ry))
                lastControlX = rx; lastControlY = ry
                currentX = x; currentY = y

            case "t":
                guard let dx = nextFloat(), let dy = nextFloat() else { break }
                let rx = 2 * currentX - lastControlX
                let ry = 2 * currentY - lastControlY
                let x = currentX + dx, y = currentY + dy
                path.addQuadCurve(to: CGPoint(x: x, y: y),
                                  control: CGPoint(x: rx, y: ry))
                lastControlX = rx; lastControlY = ry
                currentX = x; currentY = y

            case "A":
                guard let rx = nextFloat(), let ry = nextFloat(),
                      let rotation = nextFloat(),
                      let largeArc = nextFloat(), let sweep = nextFloat(),
                      let x = nextFloat(), let y = nextFloat() else { break }
                addArc(to: path,
                       from: CGPoint(x: currentX, y: currentY),
                       to: CGPoint(x: x, y: y),
                       rx: rx, ry: ry,
                       xRotation: rotation,
                       largeArc: largeArc != 0, sweep: sweep != 0)
                currentX = x; currentY = y
                lastControlX = x; lastControlY = y

            case "a":
                guard let rx = nextFloat(), let ry = nextFloat(),
                      let rotation = nextFloat(),
                      let largeArc = nextFloat(), let sweep = nextFloat(),
                      let dx = nextFloat(), let dy = nextFloat() else { break }
                let x = currentX + dx, y = currentY + dy
                addArc(to: path,
                       from: CGPoint(x: currentX, y: currentY),
                       to: CGPoint(x: x, y: y),
                       rx: rx, ry: ry,
                       xRotation: rotation,
                       largeArc: largeArc != 0, sweep: sweep != 0)
                currentX = x; currentY = y
                lastControlX = x; lastControlY = y

            case "Z", "z":
                path.closeSubpath()
                currentX = subpathStartX; currentY = subpathStartY
                lastControlX = currentX; lastControlY = currentY

            default:
                i += 1
            }

            lastCommand = cmd
        }

        return path.isEmpty ? nil : path
    }

    // MARK: - Tokenizer

    private static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        let chars = Array(d)
        var i = 0

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        while i < chars.count {
            let c = chars[i]

            if c.isWhitespace || c == "," {
                flush()
                i += 1
                continue
            }

            if c.isLetter {
                flush()
                tokens.append(String(c))
                i += 1
                continue
            }

            if c == "-" && !current.isEmpty {
                if let last = current.last, last == "e" || last == "E" {
                    current.append(c)
                    i += 1
                    continue
                }
                flush()
            }

            if c == "." && current.contains(".") {
                flush()
            }

            current.append(c)
            i += 1
        }
        flush()

        return tokens
    }

    // MARK: - Arc Conversion

    private static func addArc(to path: CGMutablePath,
                                from p1: CGPoint, to p2: CGPoint,
                                rx rxIn: CGFloat, ry ryIn: CGFloat,
                                xRotation: CGFloat,
                                largeArc: Bool, sweep: Bool)
    {
        if p1.x == p2.x && p1.y == p2.y { return }

        var rx = abs(rxIn)
        var ry = abs(ryIn)

        if rx == 0 || ry == 0 {
            path.addLine(to: p2)
            return
        }

        let phi = xRotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx = (p1.x - p2.x) / 2
        let dy = (p1.y - p2.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        let x1p2 = x1p * x1p
        let y1p2 = y1p * y1p
        var rx2 = rx * rx
        var ry2 = ry * ry
        let lambda = x1p2 / rx2 + y1p2 / ry2
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s; ry *= s
            rx2 = rx * rx; ry2 = ry * ry
        }

        var sq = (rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2) / (rx2 * y1p2 + ry2 * x1p2)
        if sq < 0 { sq = 0 }
        var root = sqrt(sq)
        if largeArc == sweep { root = -root }
        let cxp = root * rx * y1p / ry
        let cyp = -root * ry * x1p / rx

        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2

        func angle(ux: CGFloat, uy: CGFloat, vx: CGFloat, vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let theta1 = angle(ux: 1, uy: 0,
                           vx: (x1p - cxp) / rx, vy: (y1p - cyp) / ry)
        var dtheta = angle(ux: (x1p - cxp) / rx, uy: (y1p - cyp) / ry,
                           vx: (-x1p - cxp) / rx, vy: (-y1p - cyp) / ry)

        if !sweep && dtheta > 0 { dtheta -= 2 * .pi }
        if sweep && dtheta < 0 { dtheta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(dtheta) / (.pi / 2))))
        let segAngle = dtheta / CGFloat(segments)

        for s in 0..<segments {
            let t1 = theta1 + CGFloat(s) * segAngle
            let t2 = t1 + segAngle
            arcSegmentToCubic(path: path, cx: cx, cy: cy,
                              rx: rx, ry: ry, phi: phi,
                              theta1: t1, theta2: t2)
        }
    }

    private static func arcSegmentToCubic(path: CGMutablePath,
                                           cx: CGFloat, cy: CGFloat,
                                           rx: CGFloat, ry: CGFloat,
                                           phi: CGFloat,
                                           theta1: CGFloat, theta2: CGFloat)
    {
        let alpha = sin(theta2 - theta1) * (sqrt(4 + 3 * pow(tan((theta2 - theta1) / 2), 2)) - 1) / 3
        let cosPhi = cos(phi), sinPhi = sin(phi)

        func ellipsePoint(_ theta: CGFloat) -> CGPoint {
            let cosT = cos(theta), sinT = sin(theta)
            return CGPoint(
                x: cx + cosPhi * rx * cosT - sinPhi * ry * sinT,
                y: cy + sinPhi * rx * cosT + cosPhi * ry * sinT
            )
        }

        func ellipseDerivative(_ theta: CGFloat) -> CGPoint {
            let cosT = cos(theta), sinT = sin(theta)
            return CGPoint(
                x: -cosPhi * rx * sinT - sinPhi * ry * cosT,
                y: -sinPhi * rx * sinT + cosPhi * ry * cosT
            )
        }

        let ep1 = ellipsePoint(theta1)
        let ep2 = ellipsePoint(theta2)
        let d1 = ellipseDerivative(theta1)
        let d2 = ellipseDerivative(theta2)

        let cp1 = CGPoint(x: ep1.x + alpha * d1.x, y: ep1.y + alpha * d1.y)
        let cp2 = CGPoint(x: ep2.x - alpha * d2.x, y: ep2.y - alpha * d2.y)

        path.addCurve(to: ep2, control1: cp1, control2: cp2)
    }
}

// MARK: - Texture Rendering

enum SVGTextureRenderer {

    struct PathRenderOp {
        let cgPath: CGPath
        let fillColor: simd_float4
        let fillEnabled: Bool
        let strokeColor: simd_float4
        let strokeEnabled: Bool
        let strokeWidth: Float
    }

    static func render(operations: [PathRenderOp],
                       viewBox: simd_float4,
                       width: Int, height: Int,
                       device: MTLDevice) -> FabricImage?
    {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cgContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        cgContext.setShouldAntialias(true)
        cgContext.setAllowsAntialiasing(true)

        let vbX = CGFloat(viewBox.x)
        let vbY = CGFloat(viewBox.y)
        let vbW = CGFloat(max(0.001, viewBox.z))
        let vbH = CGFloat(max(0.001, viewBox.w))

        cgContext.translateBy(x: 0, y: CGFloat(height))
        cgContext.scaleBy(x: 1, y: -1)
        cgContext.scaleBy(x: CGFloat(width) / vbW, y: CGFloat(height) / vbH)
        cgContext.translateBy(x: -vbX, y: -vbY)

        for op in operations {
            if op.fillEnabled {
                let c = op.fillColor
                cgContext.setFillColor(CGColor(
                    srgbRed: CGFloat(c.x), green: CGFloat(c.y),
                    blue: CGFloat(c.z), alpha: CGFloat(c.w)))
                cgContext.addPath(op.cgPath)
                cgContext.fillPath()
            }

            if op.strokeEnabled {
                let c = op.strokeColor
                cgContext.setStrokeColor(CGColor(
                    srgbRed: CGFloat(c.x), green: CGFloat(c.y),
                    blue: CGFloat(c.z), alpha: CGFloat(c.w)))
                cgContext.setLineWidth(CGFloat(op.strokeWidth))
                cgContext.setLineCap(.round)
                cgContext.setLineJoin(.round)
                cgContext.addPath(op.cgPath)
                cgContext.strokePath()
            }
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.storageMode = .shared
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]

        guard let texture = device.makeTexture(descriptor: desc),
              let data = cgContext.data else { return nil }

        // Un-premultiply: BGRA layout [B, G, R, A]
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let count = width * height * 4
        var i = 0
        while i < count {
            let a = pixels[i + 3]
            if a > 0 && a < 255 {
                let scale = 255.0 / Float(a)
                pixels[i]     = UInt8(min(255, Float(pixels[i]) * scale))
                pixels[i + 1] = UInt8(min(255, Float(pixels[i + 1]) * scale))
                pixels[i + 2] = UInt8(min(255, Float(pixels[i + 2]) * scale))
            }
            i += 4
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: width * 4
        )

        return FabricImage.unmanaged(texture: texture)
    }
}
