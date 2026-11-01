import Fabric
import Satin
import simd
import Testing

@Suite("Stroke Geometry node")
struct StrokeGeometryNodeTests
{
    private let positions: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 0, 0], [2, 0, 0], [3, 0, 0], [4, 0, 0]]

    private func strokes(lengths: ContiguousArray<Int>,
                         widthScales: ContiguousArray<Float> = [],
                         colors: ContiguousArray<simd_float4> = []) -> [Stroke]
    {
        StrokeGeometryNode.strokes(positions: self.positions, lengths: lengths, widthScales: widthScales, colors: colors, closed: false, style: Stroke.Style())
    }

    @Test("No lengths make one stroke of every point")
    func emptyLengths()
    {
        let strokes = self.strokes(lengths: [])
        #expect(strokes.count == 1)
        #expect(strokes[0].points == self.positions)
    }

    @Test("Lengths split the points in order")
    func lengthsSplit()
    {
        let strokes = self.strokes(lengths: [2, 1, 2])
        #expect(strokes.map { Array($0.points) } == [[[0, 0, 0], [1, 0, 0]], [[2, 0, 0]], [[3, 0, 0], [4, 0, 0]]])
    }

    @Test("A length past the end is clamped, and later strokes are empty")
    func oversizedLengths()
    {
        #expect(self.strokes(lengths: [2, 100, 3]).map(\.points.count) == [2, 3, 0])
    }

    @Test("Points past the last length are unused, and a negative length takes none")
    func leftoverAndNegativeLengths()
    {
        #expect(self.strokes(lengths: [2]).map(\.points.count) == [2])
        #expect(self.strokes(lengths: [-3, 1]).map(\.points.count) == [0, 1])
    }

    @Test("Per-point arrays follow their points, and a short one repeats its last value")
    func perPointArrays()
    {
        let strokes = self.strokes(lengths: [2, 2, 1], widthScales: [1, 2, 3])
        #expect(strokes.map { Array($0.widthScales) } == [[1, 2], [3], [3]])
    }

    @Test("Style and Closed reach every stroke")
    func styleReachesEveryStroke()
    {
        let style = Stroke.Style(width: 0.5, join: .bevel, cap: .square)
        let strokes = StrokeGeometryNode.strokes(positions: self.positions, lengths: [2, 3], widthScales: [], colors: [], closed: true, style: style)
        #expect(strokes.allSatisfy { $0.style == style && $0.closed })
    }
}

@Suite("Stroke Geometry closure and dashes")
struct StrokeGeometryClosureTests
{
    private func strokes(_ points: ContiguousArray<simd_float3>, lengths: ContiguousArray<Int> = []) -> [Stroke]
    {
        StrokeGeometryNode.strokes(positions: points, lengths: lengths, widthScales: [], colors: [], closed: false, style: Stroke.Style())
    }

    @Test("A stroke returning to its start is closed, on its own")
    func closureIsPerStroke()
    {
        let result = self.strokes([[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 0, 0], [5, 5, 0], [6, 5, 0]], lengths: [4, 2])
        #expect(result[0].closed)
        #expect(!result[1].closed)
    }

    @Test("A line out and back stays open")
    func reversalStaysOpen()
    {
        #expect(!self.strokes([[0, 0, 0], [1, 0, 0], [0, 0, 0]])[0].closed)
    }

    @Test("A closed stroke dashes around its loop without a zero-length dash")
    func closedDash()
    {
        let square = self.strokes([[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 0]])[0]
        #expect(square.closed)
        let dashes = square.dashed(length: 0.5, gap: 0.5)
        #expect(dashes.count == 4)
        #expect(dashes.allSatisfy { !$0.closed && $0.points.count >= 2 })
    }

    @Test("Dashes remember their stroke, and a stroke lost to a gap keeps its place")
    func dashOrigins()
    {
        let lines = self.strokes([[0, 0, 0], [10, 0, 0], [0, 1, 0], [0.1, 1, 0]], lengths: [2, 2])
        let dashed = StrokeGeometryNode.dashed(lines, length: 1, gap: 1, offset: -1.5)
        #expect(dashed.strokes.count == dashed.origins.count)
        #expect(dashed.origins.first == 0)
        #expect(dashed.origins.last == 1)
        #expect(dashed.strokes.last?.points.isEmpty == true, "The short line starts inside a gap")
    }

    @Test("Trim applies to each stroke by its own length")
    func trimIsPerStroke()
    {
        let lines = self.strokes([[0, 0, 0], [10, 0, 0], [0, 1, 0], [2, 1, 0]], lengths: [2, 2])
        let result = StrokeGeometryNode.dashed(lines, length: 0, gap: 0, offset: 0, trimStart: 0, trimEnd: 0.5)
        #expect(result.strokes.map { Array($0.points) } == [[[0, 0, 0], [5, 0, 0]], [[0, 1, 0], [1, 1, 0]]])
        #expect(result.origins == [0, 1])
    }

    @Test("Trimming in order runs across the strokes as one line")
    func trimInOrder()
    {
        let lines = self.strokes([[0, 0, 0], [10, 0, 0], [0, 1, 0], [10, 1, 0]], lengths: [2, 2])
        let first = StrokeGeometryNode.dashed(lines, length: 0, gap: 0, offset: 0, trimStart: 0, trimEnd: 0.25, trimInOrder: true)
        #expect(first.strokes.map { Array($0.points) } == [[[0, 0, 0], [5, 0, 0]], []])
        #expect(first.origins == [0, 1])
        let second = StrokeGeometryNode.dashed(lines, length: 0, gap: 0, offset: 0, trimStart: 0.25, trimEnd: 0.75, trimInOrder: true)
        #expect(second.strokes.map { Array($0.points) } == [[[5, 0, 0], [10, 0, 0]], [[0, 1, 0], [5, 1, 0]]])
    }

    @Test("Trimming in order reaches a dot where it falls in the line")
    func trimInOrderReachesDots()
    {
        let lines = self.strokes([[0, 0, 0], [10, 0, 0], [5, 5, 0], [0, 1, 0], [10, 1, 0]], lengths: [2, 1, 2])
        let before = StrokeGeometryNode.dashed(lines, length: 0, gap: 0, offset: 0, trimEnd: 0.25, trimInOrder: true)
        #expect(before.strokes[1].points.isEmpty)
        let after = StrokeGeometryNode.dashed(lines, length: 0, gap: 0, offset: 0, trimEnd: 0.75, trimInOrder: true)
        #expect(after.strokes[1].points.count == 1)
    }

    @Test("Revealing keeps each stroke's texture in place, trimming in order too")
    func revealInOrder()
    {
        let lines = self.strokes([[0, 0, 0], [10, 0, 0], [0, 1, 0], [10, 1, 0]], lengths: [2, 2])
        let result = StrokeGeometryNode.dashed(lines, length: 0, gap: 0, offset: 0, trimEnd: 0.75, trimInOrder: true, revealingTexture: true)
        #expect(result.strokes[0].textureRange == [0, 1])
        #expect(result.strokes[1].textureRange == [0, 0.5])
    }

    @Test("Layer Depth raises the strokes in the order they are drawn")
    func layerDepthRises()
    {
        let lines = self.strokes([[0, 0, 0], [10, 0, 0], [0, 1, 0], [10, 1, 0]], lengths: [2, 2])
        let result = StrokeGeometryNode.layered(lines, depth: 2)
        #expect(result.flatMap { $0.points.map(\.z) } == [0, 1, 1, 2])
        #expect(StrokeGeometryNode.layered(lines, depth: 0) == lines)
    }

    @Test("Layer Depth keeps a closed stroke level, so its ends still meet")
    func layerDepthKeepsClosedStrokesLevel()
    {
        let lines = self.strokes([[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 0, 0], [5, 0, 0], [6, 0, 0]], lengths: [4, 2])
        let result = StrokeGeometryNode.layered(lines, depth: 1)
        #expect(result[0].closed)
        #expect(Set(result[0].points.map(\.z)) == [0])
        #expect((result[1].points.last?.z ?? 0) == 1)
    }

    @Test("Whole Path runs one texture across the strokes by length")
    func textureSpansTheWholePath()
    {
        let lines = self.strokes([[0, 0, 0], [10, 0, 0], [5, 5, 0], [0, 1, 0], [30, 1, 0]], lengths: [2, 1, 2])
        let spanned = StrokeGeometryNode.spanningTexture(lines)
        #expect(spanned.map(\.textureRange) == [[0, 0.25], [0.25, 0.25], [0.25, 1]])
    }

    @Test("Whole Path holds still under a revealing trim")
    func wholePathComposesWithReveal()
    {
        let lines = self.strokes([[0, 0, 0], [10, 0, 0], [0, 1, 0], [10, 1, 0]], lengths: [2, 2])
        let result = StrokeGeometryNode.dashed(StrokeGeometryNode.spanningTexture(lines), length: 0, gap: 0, offset: 0, trimEnd: 0.75, trimInOrder: true, revealingTexture: true)
        #expect(result.strokes[0].textureRange == [0, 0.5])
        #expect(result.strokes[1].textureRange == [0.5, 0.75])
    }

    @Test("A stroke trimmed away keeps its place")
    func trimmedAwayKeepsItsPlace()
    {
        let lines = self.strokes([[0, 0, 0], [10, 0, 0], [0, 1, 0], [2, 1, 0]], lengths: [2, 2])
        let result = StrokeGeometryNode.dashed(lines, length: 1, gap: 1, offset: 0, trimStart: 0, trimEnd: 0)
        #expect(result.origins == [0, 1])
        #expect(result.strokes.allSatisfy { $0.points.isEmpty })
    }

    @Test("Dashes hold still along the line as Trim Start moves")
    func dashesHoldStillUnderTrim()
    {
        let line = self.strokes([[0, 0, 0], [10, 0, 0]])
        let result = StrokeGeometryNode.dashed(line, length: 1, gap: 1, offset: 0, trimStart: 0.25, trimEnd: 1).strokes
        let expected: [[simd_float3]] = [[[2.5, 0, 0], [3, 0, 0]], [[4, 0, 0], [5, 0, 0]]]
        for (dash, points) in zip(result, expected)
        {
            #expect(dash.points.count == 2)
            #expect(zip(dash.points, points).allSatisfy { simd_distance($0, $1) < 1e-4 })
        }
    }

    @Test("A dot in a dashed drawing stays whole")
    func dotsSurviveDashing()
    {
        let dot = self.strokes([[1, 1, 0]])[0]
        #expect(dot.dashed(length: 1, gap: 1) == [dot])
    }
}

@Suite("Stroke Geometry colors")
struct StrokeGeometryColorTests
{
    private let red = simd_float4(1, 0, 0, 1)
    private let blue = simd_float4(0, 0, 1, 1)

    private func colors(_ colors: ContiguousArray<simd_float4>, pointCount: Int = 5) -> [simd_float4]
    {
        let points = ContiguousArray((0 ..< pointCount).map { simd_float3(Float($0), 0, 0) })
        return StrokeGeometryNode.strokes(positions: points, lengths: [], widthScales: [], colors: colors, closed: false, style: Stroke.Style())
            .flatMap { Array($0.colors) }
    }

    private func isClose(_ first: simd_float4, _ second: simd_float4) -> Bool
    {
        simd_distance(first, second) < 1e-3
    }

    @Test("One color fills every point")
    func oneColor()
    {
        let result = self.colors([self.red])
        #expect(result.count == 5)
        #expect(result.allSatisfy { self.isClose($0, self.red) })
    }

    @Test("Two colors run start to end through Oklab, not straight RGB")
    func twoColors()
    {
        let result = self.colors([self.red, self.blue])
        #expect(result.count == 5)
        #expect(self.isClose(result[0], self.red))
        #expect(self.isClose(result[4], self.blue))
        #expect(!self.isClose(result[2], simd_float4(0.5, 0, 0.5, 1)))
    }

    @Test("Three colors pass through the middle one")
    func threeColors()
    {
        let green = simd_float4(0, 1, 0, 1)
        let result = self.colors([self.red, green, self.blue])
        #expect(self.isClose(result[2], green))
    }

    @Test("Colors span every stroke in order, and a full array is untouched")
    func acrossStrokes()
    {
        let points: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 0, 0], [2, 0, 0], [3, 0, 0]]
        let strokes = StrokeGeometryNode.strokes(positions: points, lengths: [2, 2], widthScales: [], colors: [self.red, self.blue], closed: false, style: Stroke.Style())
        #expect(self.isClose(strokes[0].colors[0], self.red))
        #expect(self.isClose(strokes[1].colors[1], self.blue))
        let full: ContiguousArray<simd_float4> = [self.red, self.blue, self.red, self.blue, self.red]
        #expect(self.colors(full) == Array(full))
    }

    private func strokes(colors: ContiguousArray<simd_float4>, mode: StrokeGeometryNode.ColorMode) -> [Stroke]
    {
        let points: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 0, 0], [2, 0, 0], [3, 0, 0], [4, 0, 0], [5, 0, 0]]
        return StrokeGeometryNode.strokes(positions: points, lengths: [2, 3, 1], widthScales: [], colors: colors, colorMode: mode, closed: false, style: Stroke.Style())
    }

    @Test("Each Stroke runs the whole gradient along every stroke")
    func eachStrokeGradient()
    {
        let strokes = self.strokes(colors: [self.red, self.blue], mode: .eachStroke)
        #expect(strokes.map(\.colors.count) == [2, 3, 1])
        #expect(self.isClose(strokes[0].colors[0], self.red))
        #expect(self.isClose(strokes[0].colors[1], self.blue))
        #expect(self.isClose(strokes[1].colors[0], self.red))
        #expect(self.isClose(strokes[1].colors[2], self.blue))
    }

    @Test("Solid per Stroke steps through the gradient, one color each")
    func solidPerStroke()
    {
        let strokes = self.strokes(colors: [self.red, self.blue], mode: .solidPerStroke)
        #expect(strokes.map(\.colors.count) == [1, 1, 1])
        #expect(self.isClose(strokes[0].colors[0], self.red))
        #expect(!self.isClose(strokes[1].colors[0], self.red) && !self.isClose(strokes[1].colors[0], self.blue))
        #expect(self.isClose(strokes[2].colors[0], self.blue))
    }

    @Test("A color array matching the stroke count is used as given when solid")
    func solidPerStrokeExact()
    {
        let green = simd_float4(0, 1, 0, 1)
        let strokes = self.strokes(colors: [self.red, green, self.blue], mode: .solidPerStroke)
        #expect(strokes.map { Array($0.colors) } == [[self.red], [green], [self.blue]])
    }

    @Test("Every mode leaves no colors empty")
    func modesWithNoColors()
    {
        for mode in StrokeGeometryNode.ColorMode.allCases
        {
            #expect(self.strokes(colors: [], mode: mode).allSatisfy { $0.colors.isEmpty })
        }
    }

    @Test("No colors stay empty")
    func noColors()
    {
        #expect(self.colors([]).isEmpty)
    }
}
