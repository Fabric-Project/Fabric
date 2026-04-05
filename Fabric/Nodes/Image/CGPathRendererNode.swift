//
//  CGPathRendererNode.swift
//  Fabric
//
//  Created by Claude on 3/28/26.
//

import Foundation
import Satin
import simd
import Metal
import CoreGraphics

public class CGPathRendererNode: Node
{
    public override class var name: String { "CGPath Renderer" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .Generator) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Rasterize an SVG path d string to a texture via CoreGraphics" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            // Data input (typically from SVGImporterNode)
            ("inputPathData", ParameterPort(parameter: StringParameter("Path Data", "", .inputfield, "SVG path d attribute string"))),

            // Viewport
            ("inputWidth", ParameterPort(parameter: IntParameter("Width", 512, 1, 8192, .inputfield, "Output image width in pixels"))),
            ("inputHeight", ParameterPort(parameter: IntParameter("Height", 512, 1, 8192, .inputfield, "Output image height in pixels"))),
            ("inputViewBoxX", ParameterPort(parameter: FloatParameter("ViewBox X", 0, .inputfield, "Source viewport origin X"))),
            ("inputViewBoxY", ParameterPort(parameter: FloatParameter("ViewBox Y", 0, .inputfield, "Source viewport origin Y"))),
            ("inputViewBoxW", ParameterPort(parameter: FloatParameter("ViewBox W", 100, .inputfield, "Source viewport width"))),
            ("inputViewBoxH", ParameterPort(parameter: FloatParameter("ViewBox H", 100, .inputfield, "Source viewport height"))),

            // Style
            ("inputFillColor", ParameterPort(parameter: Float4Parameter("Fill Color", simd_float4(0, 0, 0, 1), .colorpicker, "Fill color (RGBA)"))),
            ("inputFillEnabled", ParameterPort(parameter: BoolParameter("Fill", true, .toggle, "Enable fill"))),
            ("inputStrokeColor", ParameterPort(parameter: Float4Parameter("Stroke Color", simd_float4(1, 1, 1, 1), .colorpicker, "Stroke color (RGBA)"))),
            ("inputStrokeEnabled", ParameterPort(parameter: BoolParameter("Stroke", false, .toggle, "Enable stroke"))),
            ("inputStrokeWidth", ParameterPort(parameter: FloatParameter("Stroke Width", 1.0, .inputfield, "Stroke width in SVG units"))),

            // Output
            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Rendered path image")),
        ]
    }

    public var inputPathData: ParameterPort<String> { port(named: "inputPathData") }
    public var inputWidth: ParameterPort<Int> { port(named: "inputWidth") }
    public var inputHeight: ParameterPort<Int> { port(named: "inputHeight") }
    public var inputViewBoxX: ParameterPort<Float> { port(named: "inputViewBoxX") }
    public var inputViewBoxY: ParameterPort<Float> { port(named: "inputViewBoxY") }
    public var inputViewBoxW: ParameterPort<Float> { port(named: "inputViewBoxW") }
    public var inputViewBoxH: ParameterPort<Float> { port(named: "inputViewBoxH") }
    public var inputFillColor: ParameterPort<simd_float4> { port(named: "inputFillColor") }
    public var inputFillEnabled: ParameterPort<Bool> { port(named: "inputFillEnabled") }
    public var inputStrokeColor: ParameterPort<simd_float4> { port(named: "inputStrokeColor") }
    public var inputStrokeEnabled: ParameterPort<Bool> { port(named: "inputStrokeEnabled") }
    public var inputStrokeWidth: ParameterPort<Float> { port(named: "inputStrokeWidth") }
    public var outputTexturePort: NodePort<FabricImage> { port(named: "outputTexturePort") }

    // Cached path parse
    @ObservationIgnored private var cachedPathHash: Int?
    @ObservationIgnored private var cachedCGPath: CGPath?

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

        guard let pathString = inputPathData.value, !pathString.isEmpty else {
            outputTexturePort.send(nil)
            return
        }

        let width = max(1, inputWidth.value ?? 512)
        let height = max(1, inputHeight.value ?? 512)

        // Parse d string (cached)
        let hash = pathString.hashValue
        let cgPath: CGPath
        if hash == cachedPathHash, let cached = cachedCGPath {
            cgPath = cached
        } else {
            guard let parsed = CGPathRendererNode.parseSVGPathData(pathString) else {
                outputTexturePort.send(nil)
                return
            }
            cgPath = parsed
            cachedPathHash = hash
            cachedCGPath = parsed
        }

        // Create CGContext
        guard let cgContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            outputTexturePort.send(nil)
            return
        }

        cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))

        // ViewBox transform: map SVG coordinates → pixel coordinates
        // CGContext is bottom-left origin; SVG is top-left, so flip Y
        let vbX = CGFloat(inputViewBoxX.value ?? 0)
        let vbY = CGFloat(inputViewBoxY.value ?? 0)
        let vbW = CGFloat(max(0.001, inputViewBoxW.value ?? 100))
        let vbH = CGFloat(max(0.001, inputViewBoxH.value ?? 100))

        cgContext.translateBy(x: 0, y: CGFloat(height))
        cgContext.scaleBy(x: 1, y: -1)
        cgContext.scaleBy(x: CGFloat(width) / vbW, y: CGFloat(height) / vbH)
        cgContext.translateBy(x: -vbX, y: -vbY)

        // Fill
        if inputFillEnabled.value ?? true {
            let c = inputFillColor.value ?? simd_float4(0, 0, 0, 1)
            cgContext.setFillColor(CGColor(
                srgbRed: CGFloat(c.x), green: CGFloat(c.y),
                blue: CGFloat(c.z), alpha: CGFloat(c.w)))
            cgContext.addPath(cgPath)
            cgContext.fillPath()
        }

        // Stroke
        if inputStrokeEnabled.value ?? false {
            let c = inputStrokeColor.value ?? simd_float4(1, 1, 1, 1)
            let sw = CGFloat(inputStrokeWidth.value ?? 1)
            cgContext.setStrokeColor(CGColor(
                srgbRed: CGFloat(c.x), green: CGFloat(c.y),
                blue: CGFloat(c.z), alpha: CGFloat(c.w)))
            cgContext.setLineWidth(sw)
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)
            cgContext.addPath(cgPath)
            cgContext.strokePath()
        }

        // Upload to MTLTexture
        let device = context.graphRenderer!.context.device
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: desc),
              let data = cgContext.data else {
            outputTexturePort.send(nil)
            return
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: width * 4
        )

        let outImage = FabricImage.unmanaged(texture: texture)
        outputTexturePort.send(outImage)
    }
}

// MARK: - SVG path d string → CGPath parser

extension CGPathRendererNode {

    /// Parse an SVG path `d` attribute string into a CGPath.
    /// Supports: M/m, L/l, H/h, V/v, C/c, S/s, Q/q, T/t, A/a, Z/z
    fileprivate static func parseSVGPathData(_ d: String) -> CGPath?
    {
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

            // If it's a number and the last command accepts implicit repeats, reuse the command
            let cmd: Character
            if let first = token.first, (first.isNumber || first == "-" || first == "+" || first == ".") {
                // Implicit repeat of last command (M becomes L after first pair, m becomes l)
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
                // Reflect last control point
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
                i += 1  // skip unknown
            }

            lastCommand = cmd
        }

        return path.isEmpty ? nil : path
    }

    // MARK: - Tokenizer

    /// Split an SVG path `d` string into command letters and number tokens.
    private static func tokenize(_ d: String) -> [String]
    {
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

            // Command letter
            if c.isLetter {
                flush()
                tokens.append(String(c))
                i += 1
                continue
            }

            // Minus sign: starts a new number (unless we're at the start of current)
            if c == "-" && !current.isEmpty {
                // Check if this minus follows an 'e'/'E' (scientific notation)
                if let last = current.last, last == "e" || last == "E" {
                    current.append(c)
                    i += 1
                    continue
                }
                flush()
            }

            // Dot: if current already has a dot, start new token
            if c == "." && current.contains(".") {
                flush()
            }

            current.append(c)
            i += 1
        }
        flush()

        return tokens
    }

    // MARK: - Arc conversion (endpoint → center parameterization → cubic beziers)

    /// Convert an SVG elliptical arc to cubic bezier curves appended to the path.
    /// Uses the SVG spec's endpoint-to-center conversion algorithm.
    private static func addArc(to path: CGMutablePath,
                               from p1: CGPoint, to p2: CGPoint,
                               rx rxIn: CGFloat, ry ryIn: CGFloat,
                               xRotation: CGFloat,
                               largeArc: Bool, sweep: Bool)
    {
        // Degenerate: same point
        if p1.x == p2.x && p1.y == p2.y { return }

        var rx = abs(rxIn)
        var ry = abs(ryIn)

        // Degenerate: zero radius → line
        if rx == 0 || ry == 0 {
            path.addLine(to: p2)
            return
        }

        let phi = xRotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        // Step 1: compute (x1', y1')
        let dx = (p1.x - p2.x) / 2
        let dy = (p1.y - p2.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // Ensure radii are large enough
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

        // Step 2: compute (cx', cy')
        var sq = (rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2) / (rx2 * y1p2 + ry2 * x1p2)
        if sq < 0 { sq = 0 }
        var root = sqrt(sq)
        if largeArc == sweep { root = -root }
        let cxp = root * rx * y1p / ry
        let cyp = -root * ry * x1p / rx

        // Step 3: compute (cx, cy)
        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2

        // Step 4: compute theta1 and dtheta
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

        // Split into segments of at most pi/2
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

    /// Approximate a single arc segment (≤ π/2) with a cubic bezier.
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
