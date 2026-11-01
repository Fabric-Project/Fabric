//
//  StrokeGeometryNode.swift
//  Fabric
//

import Foundation
import Satin
import simd

/// Draws arrays of points as ribbons with joins and caps. Stroke Lengths splits Positions into
/// separate lines with gaps between them, and a stroke of one point with a Round cap is a dot.
public final class StrokeGeometryNode: BaseGeometryNode
{
    /// How the Colors array spreads over the strokes.
    public enum ColorMode: String, CaseIterable
    {
        /// One gradient across every point, whichever stroke it is in.
        case allPoints = "All Points"
        /// The whole gradient along each stroke.
        case eachStroke = "Each Stroke" 
        /// One solid color per stroke, stepping through the gradient from the first stroke to the last.
        case solidPerStroke = "Solid per Stroke"
    }

    public override class var name: String { "Stroke Geometry" }
    public override class var nodeDescription: String { "Draws an array of positions as ribbons, with a width, joins and caps. Stroke Lengths splits the positions into separate lines with gaps between them. A stroke of one point with a Round cap is a dot. Per-point colors show in materials that read vertex color, such as Standard and PBR." }

    private static let joinTitles = ["Miter", "Bevel", "Round"]
    private static let capTitles = ["Butt", "Square", "Round"]
    private static let piecesNone = "None"
    private static let piecesStrokes = "Strokes"
    private static let piecesStrokesAndDashes = "Strokes and Dashes"
    private static let trimEachStroke = "Each Stroke"
    private static let trimAllInOrder = "All Strokes in Order"
    private static let textureStretch = "Stretch"
    private static let textureReveal = "Reveal"
    private static let textureEachPiece = "Each Piece"
    private static let textureWholePath = "Whole Path"

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return [
            ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet, description: "Every point, one stroke after another")),
            ("inputStrokeLengths", NodePort<ContiguousArray<Int>>(name: "Stroke Lengths", kind: .Inlet, description: "How many points each stroke takes from Positions, in order. Not connected or empty draws one stroke through every point")),
            ("inputWidthScales", NodePort<ContiguousArray<Float>>(name: "Width Scales", kind: .Inlet, description: "Multiplies Width per point, across every stroke. The last value repeats")),
            ("inputColors", NodePort<ContiguousArray<simd_float4>>(name: "Colors", kind: .Inlet, description: "Vertex colors spread evenly as Color Mode says, interpolated in Oklab: one color fills them all, two run from start to end, three through a middle, and so on")),
            ("inputColorMode", ParameterPort(parameter: StringParameter("Color Mode", ColorMode.allPoints.rawValue, ColorMode.allCases.map(\.rawValue), .dropdown, "Spreads Colors across every point, along each stroke, or as one solid color per stroke"))),
            ("inputClosed", ParameterPort(parameter: BoolParameter("Closed", false, .button, "When enabled, every stroke returns to its first point. A stroke whose last point repeats its first is always closed"))),
            ("inputWidth", ParameterPort(parameter: FloatParameter("Width", 0.1, .inputfield, "Ribbon width in world units"))),
            ("inputJoin", ParameterPort(parameter: StringParameter("Join", "Round", Self.joinTitles, .dropdown, "The shape where two segments meet"))),
            ("inputCap", ParameterPort(parameter: StringParameter("Cap", "Round", Self.capTitles, .dropdown, "The shape at each end of an open stroke"))),
            ("inputLayerDepth", ParameterPort(parameter: FloatParameter("Layer Depth", 0, 0, 10, .inputfield, "How far the lines rise off their plane from first point to last, in world units, so a later part always draws over an earlier one where they cross. Raise it if crossings flicker at an angle. Only enough to stop that: more shows as a tilt"))),
            ("inputTrimStart", ParameterPort(parameter: FloatParameter("Trim Start", 0, 0, 1, .slider, "Where the lines begin, as a fraction of their length. Wire time into this or Trim End to reveal them"))),
            ("inputTrimEnd", ParameterPort(parameter: FloatParameter("Trim End", 1, 0, 1, .slider, "Where the lines end, as a fraction of their length"))),
            ("inputTrimMode", ParameterPort(parameter: StringParameter("Trim Mode", Self.trimEachStroke, [Self.trimEachStroke, Self.trimAllInOrder], .dropdown, "Trims every stroke by its own length, or treats the strokes as one line drawn in order"))),
            ("inputTextureMode", ParameterPort(parameter: StringParameter("Texture Mode", Self.textureStretch, [Self.textureStretch, Self.textureReveal], .dropdown, "Stretches the whole texture over what a trim or dash leaves, or holds the texture still on the line so they reveal it"))),
            ("inputTextureSpan", ParameterPort(parameter: StringParameter("Texture Span", Self.textureEachPiece, [Self.textureEachPiece, Self.textureWholePath], .dropdown, "Runs the texture from 0 to 1 along each piece, or once along the whole path, from the first stroke to the last"))),
            ("inputDashLength", ParameterPort(parameter: FloatParameter("Dash Length", 0, 0, 100, .inputfield, "The length of each dash along the line, in world units. 0 draws solid lines"))),
            ("inputGapLength", ParameterPort(parameter: FloatParameter("Gap Length", 0.1, 0, 100, .inputfield, "The space between dashes, in world units. 0 draws solid lines"))),
            ("inputDashOffset", ParameterPort(parameter: FloatParameter("Dash Offset", 0, -1000, 1000, .inputfield, "Slides the dashes along the line, in world units. Wire time into this to make them march"))),
            ("inputPieces", ParameterPort(parameter: StringParameter("Pieces", Self.piecesNone, [Self.piecesNone, Self.piecesStrokes, Self.piecesStrokesAndDashes], .dropdown, "Divides the geometry into pieces for Transform Pieces and Piece Info: one per stroke, or one per stroke with its dashes as children. Rebuilding pieces adds cost when the lines animate"))),
            ("inputMiterLimit", ParameterPort(parameter: FloatParameter("Miter Limit", 4, .inputfield, "How far a Miter join may reach, in half-widths, before it becomes a Bevel"))),
        ] + ports
    }

    public var inputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "inputPositions") }
    public var inputStrokeLengths: NodePort<ContiguousArray<Int>> { port(named: "inputStrokeLengths") }
    public var inputWidthScales: NodePort<ContiguousArray<Float>> { port(named: "inputWidthScales") }
    public var inputColors: NodePort<ContiguousArray<simd_float4>> { port(named: "inputColors") }
    public var inputColorMode: ParameterPort<String> { port(named: "inputColorMode") }
    public var inputClosed: ParameterPort<Bool> { port(named: "inputClosed") }
    public var inputWidth: ParameterPort<Float> { port(named: "inputWidth") }
    public var inputJoin: ParameterPort<String> { port(named: "inputJoin") }
    public var inputCap: ParameterPort<String> { port(named: "inputCap") }
    public var inputLayerDepth: ParameterPort<Float> { port(named: "inputLayerDepth") }
    public var inputTrimStart: ParameterPort<Float> { port(named: "inputTrimStart") }
    public var inputTrimEnd: ParameterPort<Float> { port(named: "inputTrimEnd") }
    public var inputTrimMode: ParameterPort<String> { port(named: "inputTrimMode") }
    public var inputTextureMode: ParameterPort<String> { port(named: "inputTextureMode") }
    public var inputTextureSpan: ParameterPort<String> { port(named: "inputTextureSpan") }
    public var inputDashLength: ParameterPort<Float> { port(named: "inputDashLength") }
    public var inputGapLength: ParameterPort<Float> { port(named: "inputGapLength") }
    public var inputDashOffset: ParameterPort<Float> { port(named: "inputDashOffset") }
    public var inputPieces: ParameterPort<String> { port(named: "inputPieces") }
    public var inputMiterLimit: ParameterPort<Float> { port(named: "inputMiterLimit") }

    public override var geometry: StrokeGeometry { _geometry }

    private lazy var _geometry = StrokeGeometry(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputPositions.valueDidChange
            || self.inputStrokeLengths.valueDidChange
            || self.inputWidthScales.valueDidChange
            || self.inputColors.valueDidChange
            || self.inputColorMode.valueDidChange
            || self.inputClosed.valueDidChange
            || self.inputWidth.valueDidChange
            || self.inputJoin.valueDidChange
            || self.inputCap.valueDidChange
            || self.inputLayerDepth.valueDidChange
            || self.inputTrimStart.valueDidChange
            || self.inputTrimEnd.valueDidChange
            || self.inputTrimMode.valueDidChange
            || self.inputTextureMode.valueDidChange
            || self.inputTextureSpan.valueDidChange
            || self.inputDashLength.valueDidChange
            || self.inputGapLength.valueDidChange
            || self.inputDashOffset.valueDidChange
            || self.inputPieces.valueDidChange
            || self.inputMiterLimit.valueDidChange
        {
            let style = Stroke.Style(width: self.inputWidth.value ?? 0.1,
                                     join: Self.join(named: self.inputJoin.value),
                                     cap: Self.cap(named: self.inputCap.value),
                                     miterLimit: self.inputMiterLimit.value ?? 4)
            let strokes = Self.strokes(positions: self.inputPositions.value ?? [],
                                                       lengths: self.inputStrokeLengths.value ?? [],
                                                       widthScales: self.inputWidthScales.value ?? [],
                                                       colors: self.inputColors.value ?? [],
                                                       colorMode: ColorMode(rawValue: self.inputColorMode.value ?? "") ?? .allPoints,
                                                       closed: self.inputClosed.value ?? false,
                                                       style: style)
            let dashLength = self.inputDashLength.value ?? 0
            let gapLength = self.inputGapLength.value ?? 0
            let dashOffset = self.inputDashOffset.value ?? 0
            let layered = Self.layered(strokes, depth: self.inputLayerDepth.value ?? 0)
            let revealingTexture = self.inputTextureMode.value == Self.textureReveal
            let spansWholePath = self.inputTextureSpan.value == Self.textureWholePath
            // Revealing holds the whole path's texture still under the cuts. Stretching fits it to what they leave.
            var dashed = Self.dashed(spansWholePath && revealingTexture ? Self.spanningTexture(layered) : layered,
                                     length: dashLength, gap: gapLength, offset: dashOffset,
                                     trimStart: self.inputTrimStart.value ?? 0,
                                     trimEnd: self.inputTrimEnd.value ?? 1,
                                     trimInOrder: self.inputTrimMode.value == Self.trimAllInOrder,
                                     revealingTexture: revealingTexture)
            if spansWholePath && !revealingTexture { dashed.strokes = Self.spanningTexture(dashed.strokes) }
            let pieces: StrokePieces
            switch self.inputPieces.value
            {
            case Self.piecesStrokes: pieces = .mergedGroups(dashed.origins)
            case Self.piecesStrokesAndDashes: pieces = .groups(dashed.origins)
            default: pieces = .none
            }
            self.geometry.update(strokes: dashed.strokes, pieces: pieces)
            shouldOutputGeometry = true
        }

        return shouldOutputGeometry
    }

    /// Splits flat per-point arrays into strokes. Empty lengths make one stroke of every point;
    /// a length past the end of `positions` is clamped, and points past the last length are unused.
    /// Width scales repeat their last value, and colors spread as `colorMode` says.
    public static func strokes(positions: ContiguousArray<simd_float3>,
                        lengths: ContiguousArray<Int>,
                        widthScales: ContiguousArray<Float>,
                        colors: ContiguousArray<simd_float4>,
                        colorMode: ColorMode = .allPoints,
                        closed: Bool,
                        style: Stroke.Style) -> [Stroke]
    {
        let strokeLengths = lengths.isEmpty ? [positions.count] : Array(lengths)
        let spreadColors: ContiguousArray<simd_float4>
        switch colorMode
        {
        case .allPoints: spreadColors = Self.colorsMatching(pointCount: positions.count, colors: colors)
        case .eachStroke: spreadColors = colors
        case .solidPerStroke: spreadColors = Self.colorsMatching(pointCount: strokeLengths.count, colors: colors)
        }
        var strokes: [Stroke] = []
        strokes.reserveCapacity(strokeLengths.count)

        var start = 0
        for (strokeIndex, length) in strokeLengths.enumerated()
        {
            let end = min(start + max(0, length), positions.count)
            let points = ContiguousArray(positions[start ..< end])
            let strokeColors: ContiguousArray<simd_float4>
            switch colorMode
            {
            case .allPoints: strokeColors = Self.values(of: spreadColors, from: start, to: end)
            case .eachStroke: strokeColors = Self.colorsMatching(pointCount: points.count, colors: spreadColors)
            case .solidPerStroke: strokeColors = Self.values(of: spreadColors, from: strokeIndex, to: strokeIndex + 1)
            }
            strokes.append(Stroke(points: points,
                                  closed: closed || Self.returnsToStart(points),
                                  colors: strokeColors,
                                  style: style,
                                  widthScales: Self.values(of: widthScales, from: start, to: end)))
            start = end
        }

        return strokes
    }

    /// Every stroke's share of one texture run from 0 to 1 across all of them, by length, in order.
    public static func spanningTexture(_ strokes: [Stroke]) -> [Stroke]
    {
        let allLength = strokes.reduce(Float(0)) { $0 + $1.totalLength }
        guard allLength > 0 else { return strokes }

        var walked: Float = 0
        return strokes.map { stroke in
            var result = stroke
            let start = walked
            walked += stroke.totalLength
            result.textureRange = [start / allLength, walked / allLength]
            return result
        }
    }

    /// Every stroke raised along its `up` by how far along all the strokes each point is, reaching
    /// `depth` at the end of the last, so a later part draws over an earlier one where they cross.
    /// A closed stroke stays level, at the height it starts, so its ends still meet.
    public static func layered(_ strokes: [Stroke], depth: Float) -> [Stroke]
    {
        let allLength = strokes.reduce(Float(0)) { $0 + $1.totalLength }
        guard depth > 0, allLength > 0 else { return strokes }

        var walked: Float = 0
        return strokes.map { stroke in
            var result = stroke
            let up = simd_length(stroke.style.up) > 0 ? simd_normalize(stroke.style.up) : simd_float3(0, 0, 1)
            let start = walked
            for index in stroke.points.indices
            {
                if !stroke.closed, index > 0 { walked += simd_distance(stroke.points[index - 1], stroke.points[index]) }
                result.points[index] += up * depth * walked / allLength
            }
            if stroke.closed { walked = start + stroke.totalLength }
            return result
        }
    }

    /// Every stroke trimmed and cut into dashes, and which stroke each dash came from. Dashes hold still
    /// along the line as a trim moves. A stroke falling wholly in a gap or outside the trim leaves an
    /// empty stroke, so piece order still follows the input. `trimInOrder` measures the trim along every
    /// stroke as one line, where a dot appears once the range reaches it; with no length to measure,
    /// each stroke trims alone.
    public static func dashed(_ strokes: [Stroke], length: Float, gap: Float, offset: Float, trimStart: Float = 0, trimEnd: Float = 1, trimInOrder: Bool = false, revealingTexture: Bool = false) -> (strokes: [Stroke], origins: [Int])
    {
        let allLength = trimInOrder ? strokes.reduce(Float(0)) { $0 + $1.totalLength } : 0
        let rangeStart = min(max(min(trimStart, trimEnd), 0), 1) * allLength
        let rangeEnd = min(max(max(trimStart, trimEnd), 0), 1) * allLength
        var walked: Float = 0
        var dashedStrokes: [Stroke] = []
        var origins: [Int] = []
        dashedStrokes.reserveCapacity(strokes.count)
        for (origin, stroke) in strokes.enumerated()
        {
            let strokeLength = stroke.totalLength
            var strokeStart = trimStart
            var strokeEnd = trimEnd
            if allLength > 0
            {
                if strokeLength > 0
                {
                    strokeStart = (rangeStart - walked) / strokeLength
                    strokeEnd = (rangeEnd - walked) / strokeLength
                }
                else
                {
                    let reached = rangeStart < rangeEnd && rangeStart <= walked && (walked < rangeEnd || rangeEnd == allLength)
                    strokeStart = 0
                    strokeEnd = reached ? 1 : 0
                }
                walked += strokeLength
            }
            let trimmed = stroke.trimmed(start: strokeStart, end: strokeEnd, revealingTexture: revealingTexture)
            let trimmedAway = max(min(strokeStart, strokeEnd), 0) * strokeLength
            let cut = trimmed.dashed(length: length, gap: gap, offset: offset - trimmedAway, revealingTexture: revealingTexture)
            let dashes = cut.isEmpty ? [Stroke(points: [], style: stroke.style)] : cut
            dashedStrokes.append(contentsOf: dashes)
            origins.append(contentsOf: repeatElement(origin, count: dashes.count))
        }
        return (dashedStrokes, origins)
    }

    /// A stroke whose last point repeats its first is a closed shape, so it joins there instead of
    /// capping. Three points would only be a line out and back.
    private static func returnsToStart(_ points: ContiguousArray<simd_float3>) -> Bool
    {
        guard points.count > 3, let first = points.first, let last = points.last else { return false }
        return simd_distance(first, last) <= 1e-6
    }

    /// `colors` spread evenly across every point, in order, interpolated in Oklab: one color fills
    /// them all, two run from start to end, three from start through middle to end, and so on.
    private static func colorsMatching(pointCount: Int, colors: ContiguousArray<simd_float4>) -> ContiguousArray<simd_float4>
    {
        guard !colors.isEmpty, colors.count != pointCount else { return colors }
        let boxedColors = colors.map { $0.toPortValue() }
        let resampled = NumericValueOperations.resampleArray(ContiguousArray(boxedColors), count: pointCount, elementType: .Color)
        return ContiguousArray(resampled.compactMap { simd_float4.fromPortValue($0) })
    }

    /// One stroke's share of a per-point array: past the array's end, its last value repeats.
    private static func values<Value>(of array: ContiguousArray<Value>, from start: Int, to end: Int) -> ContiguousArray<Value>
    {
        guard let last = array.last else { return [] }
        guard start < array.count else { return [last] }
        return ContiguousArray(array[start ..< min(end, array.count)])
    }

    private static func join(named name: String?) -> Stroke.Join
    {
        switch name
        {
        case "Miter": return .miter
        case "Bevel": return .bevel
        default: return .round
        }
    }

    private static func cap(named name: String?) -> Stroke.Cap
    {
        switch name
        {
        case "Butt": return .butt
        case "Square": return .square
        default: return .round
        }
    }
}
