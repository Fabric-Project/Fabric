import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

/// Correctness coverage for `Satin.PolylineGeometry` (backed by SatinCore's
/// `generatePolylineGeometryData`) — joins, caps, closed loops, degenerate
/// inputs, and the front-facing-winding regression that caught the
/// bevel/round join seam bug and the round end-cap winding bug (vertex/index
/// *counts* alone don't catch either). This suite superseded a pure-Swift
/// reference implementation once `PolylineGeometryDifferentialTests` (no
/// longer in the tree) confirmed the SatinCore port matched it exactly.
@Suite("Polyline Geometry")
struct PolylineGeometryTests
{
    private func makeContext() -> Context?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
    }

    private func tessellate(
        context: Context,
        points: ContiguousArray<simd_float3>,
        closed: Bool = false,
        width: Float = 1.0,
        joinStyle: PolylineJoinStyle = .miter,
        capStyle: PolylineCapStyle = .butt,
        miterLimit: Float = 4.0,
        up: simd_float3 = simd_float3(0, 0, 1),
        roundResolution: Int = 8,
        speedWidthAmount: Float = 0.0,
        speedWidthMinMultiplier: Float = 0.25,
        speedWidthMaxMultiplier: Float = 1.0,
        pointColors: ContiguousArray<simd_float4>? = nil
    ) -> PolylineGeometry
    {
        let geometry = PolylineGeometry(context: context)
        geometry.update(
            points: points, closed: closed, width: width,
            joinStyle: joinStyle, capStyle: capStyle, miterLimit: miterLimit,
            up: up, roundResolution: roundResolution,
            speedWidthAmount: speedWidthAmount,
            speedWidthMinMultiplier: speedWidthMinMultiplier,
            speedWidthMaxMultiplier: speedWidthMaxMultiplier,
            pointColors: pointColors
        )
        return geometry
    }

    /// Every non-degenerate triangle's winding must produce a normal on the
    /// same side as `referenceNormal` — i.e. front-facing under default
    /// back-face culling.
    private func allTrianglesFrontFacing(_ geometry: PolylineGeometry, referenceNormal: simd_float3) -> Bool
    {
        var checkedAny = false
        for t in 0 ..< geometry.triangleCount
        {
            let (i0, i1, i2) = geometry.triangleIndices(at: t)
            let a = geometry.position(at: Int(i0))
            let b = geometry.position(at: Int(i1))
            let c = geometry.position(at: Int(i2))
            let faceNormal = cross(b - a, c - a)

            guard simd_length(faceNormal) > 1e-8 else { continue }
            guard dot(faceNormal, referenceNormal) > 0 else { return false }
            checkedAny = true
        }
        return checkedAny
    }

    @Test func degenerateInputsProduceEmptyGeometry() throws
    {
        guard let context = makeContext() else { return }

        #expect(tessellate(context: context, points: []).vertexCount == 0)
        #expect(tessellate(context: context, points: [simd_float3(0, 0, 0)]).vertexCount == 0)
        #expect(tessellate(context: context, points: [simd_float3(0, 0, 0)], closed: true).vertexCount == 0)
        #expect(tessellate(context: context, points: [simd_float3(0, 0, 0), simd_float3(1, 0, 0)], width: 0).vertexCount == 0)
    }

    @Test func duplicateConsecutivePointsAreCollapsed() throws
    {
        guard let context = makeContext() else { return }

        let points: ContiguousArray<simd_float3> = [
            simd_float3(0, 0, 0), simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(1, 0, 0),
        ]
        let geometry = tessellate(context: context, points: points)

        #expect(geometry.vertexCount == 4)
        #expect(geometry.triangleCount == 2)
    }

    @Test func straightOpenSegmentProducesOneQuadNoJoinGeometry() throws
    {
        guard let context = makeContext() else { return }

        let points: ContiguousArray<simd_float3> = [simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(2, 0, 0)]
        let geometry = tessellate(context: context, points: points, capStyle: .butt)

        #expect(geometry.vertexCount == 6)
        #expect(geometry.triangleCount == 4)
    }

    @Test func sharpTurnExceedsMiterLimitAndFallsBackToBevel() throws
    {
        guard let context = makeContext() else { return }

        let points: ContiguousArray<simd_float3> = [simd_float3(-1, 0, 0), simd_float3(0, 0, 0), simd_float3(-1, 0.001, 0)]
        let geometry = tessellate(context: context, points: points, joinStyle: .miter, miterLimit: 4.0)

        let cornerTypes = (0 ..< geometry.vertexCount).map { geometry.custom0(at: $0).z }
        #expect(cornerTypes.contains(2))
        #expect(!cornerTypes.contains(1))
    }

    @Test func moderateTurnWithinMiterLimitStaysMiter() throws
    {
        guard let context = makeContext() else { return }

        let points: ContiguousArray<simd_float3> = [simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(2, 0.1, 0)]
        let geometry = tessellate(context: context, points: points, joinStyle: .miter, miterLimit: 4.0)

        let cornerTypes = (0 ..< geometry.vertexCount).map { geometry.custom0(at: $0).z }
        #expect(cornerTypes.contains(1))
        #expect(!cornerTypes.contains(2))
    }

    @Test func closedLoopEmitsNoCapGeometryAndWrapsIndices() throws
    {
        guard let context = makeContext() else { return }

        let points: ContiguousArray<simd_float3> = [
            simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(1, 1, 0), simd_float3(0, 1, 0),
        ]
        let geometry = tessellate(context: context, points: points, closed: true, joinStyle: .bevel)

        let cornerTypes = (0 ..< geometry.vertexCount).map { geometry.custom0(at: $0).z }
        #expect(!cornerTypes.contains(3))

        for t in 0 ..< geometry.triangleCount
        {
            let (i0, i1, i2) = geometry.triangleIndices(at: t)
            #expect(Int(i0) < geometry.vertexCount && Int(i1) < geometry.vertexCount && Int(i2) < geometry.vertexCount)
        }
        #expect(geometry.vertexCount > 0)
    }

    @Test func roundJoinAndCapProduceMoreVerticesThanBevel() throws
    {
        guard let context = makeContext() else { return }

        let points: ContiguousArray<simd_float3> = [simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(1, 1, 0)]
        let bevel = tessellate(context: context, points: points, joinStyle: .bevel, capStyle: .butt)
        let round = tessellate(context: context, points: points, joinStyle: .round, capStyle: .round, roundResolution: 8)

        #expect(round.vertexCount > bevel.vertexCount)
        #expect(round.triangleCount > bevel.triangleCount)
    }

    @Test func segmentParallelToUpVectorDoesNotProduceNaNs() throws
    {
        guard let context = makeContext() else { return }

        let points: ContiguousArray<simd_float3> = [simd_float3(0, 0, 0), simd_float3(0, 0, 1), simd_float3(0, 0, 2)]
        let geometry = tessellate(context: context, points: points, up: simd_float3(0, 0, 1))

        #expect(geometry.vertexCount > 0)
        for i in 0 ..< geometry.vertexCount
        {
            let p = geometry.position(at: i)
            #expect(p.x.isFinite && p.y.isFinite && p.z.isFinite)
        }
    }

    @Test func squareCapExtendsPastEndpointAlongTangent() throws
    {
        guard let context = makeContext() else { return }

        let points: ContiguousArray<simd_float3> = [simd_float3(0, 0, 0), simd_float3(1, 0, 0)]
        let butt = tessellate(context: context, points: points, width: 0.2, capStyle: .butt)
        let square = tessellate(context: context, points: points, width: 0.2, capStyle: .square)

        let buttMaxX = (0 ..< butt.vertexCount).map { butt.position(at: $0).x }.max() ?? 0
        let squareMaxX = (0 ..< square.vertexCount).map { square.position(at: $0).x }.max() ?? 0

        #expect(squareMaxX > buttMaxX)
    }

    @Test func bevelJoinIsFrontFacingForBothTurnDirections() throws
    {
        guard let context = makeContext() else { return }

        let referenceNormal = simd_float3(0, 0, 1)
        let leftTurn: ContiguousArray<simd_float3> = [simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(1, 1, 0)]
        let rightTurn: ContiguousArray<simd_float3> = [simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(1, -1, 0)]

        #expect(allTrianglesFrontFacing(tessellate(context: context, points: leftTurn, joinStyle: .bevel), referenceNormal: referenceNormal))
        #expect(allTrianglesFrontFacing(tessellate(context: context, points: rightTurn, joinStyle: .bevel), referenceNormal: referenceNormal))
    }

    @Test func roundJoinIsFrontFacingForBothTurnDirections() throws
    {
        guard let context = makeContext() else { return }

        let referenceNormal = simd_float3(0, 0, 1)
        let leftTurn: ContiguousArray<simd_float3> = [simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(1, 1, 0)]
        let rightTurn: ContiguousArray<simd_float3> = [simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(1, -1, 0)]

        #expect(allTrianglesFrontFacing(tessellate(context: context, points: leftTurn, joinStyle: .round, roundResolution: 6), referenceNormal: referenceNormal))
        #expect(allTrianglesFrontFacing(tessellate(context: context, points: rightTurn, joinStyle: .round, roundResolution: 6), referenceNormal: referenceNormal))
    }

    @Test func closedLoopBevelAndRoundJoinsAreFrontFacingInBothWindingDirections() throws
    {
        guard let context = makeContext() else { return }

        let referenceNormal = simd_float3(0, 0, 1)
        let ccwSquare: ContiguousArray<simd_float3> = [
            simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(1, 1, 0), simd_float3(0, 1, 0),
        ]
        let cwSquare = ContiguousArray(ccwSquare.reversed())

        for square in [ccwSquare, cwSquare]
        {
            #expect(allTrianglesFrontFacing(tessellate(context: context, points: square, closed: true, joinStyle: .bevel), referenceNormal: referenceNormal))
            #expect(allTrianglesFrontFacing(tessellate(context: context, points: square, closed: true, joinStyle: .round, roundResolution: 6), referenceNormal: referenceNormal))
        }
    }

    @Test func speedWidthAmountZeroLeavesWidthUniformRegardlessOfSpacing() throws
    {
        guard let context = makeContext() else { return }

        let points: ContiguousArray<simd_float3> = [
            simd_float3(0, 0, 0), simd_float3(0.1, 0, 0), simd_float3(1.1, 0, 0), simd_float3(1.2, 0, 0),
        ]
        let geometry = tessellate(context: context, points: points, width: 1.0, speedWidthAmount: 0.0)

        for i in 0 ..< geometry.vertexCount
        {
            #expect(abs(geometry.custom0(at: i).y - 1.0) < 1e-5)
        }
    }

    @Test func speedWidthAmountTapersWidthAtWidelySpacedPoints() throws
    {
        guard let context = makeContext() else { return }

        // Segment lengths: 0.1, 1.0, 0.1 — P0/P3 sit only beside the short ("slow")
        // segment; P1/P2 sit beside the long ("fast") segment.
        let points: ContiguousArray<simd_float3> = [
            simd_float3(0, 0, 0), simd_float3(0.1, 0, 0), simd_float3(1.1, 0, 0), simd_float3(1.2, 0, 0),
        ]
        let geometry = tessellate(
            context: context, points: points, width: 1.0,
            speedWidthAmount: 1.0, speedWidthMinMultiplier: 0.25, speedWidthMaxMultiplier: 1.0
        )

        var maxOffsetByCore: [SIMD3<Float>: Float] = [:]
        for i in 0 ..< geometry.vertexCount
        {
            let core = geometry.custom1(at: i)
            let offset = simd_length(geometry.position(at: i) - core)
            maxOffsetByCore[core] = max(maxOffsetByCore[core] ?? 0, offset)
        }

        let p0Offset = try #require(maxOffsetByCore[simd_float3(0, 0, 0)])
        let p1Offset = try #require(maxOffsetByCore[simd_float3(0.1, 0, 0)])
        let p3Offset = try #require(maxOffsetByCore[simd_float3(1.2, 0, 0)])

        #expect(p1Offset < p0Offset)
        #expect(p1Offset < p3Offset)
        #expect(p0Offset > 0.4) // near the full half-width (0.5) at max multiplier 1.0
    }

    @Test func speedWidthAttenuationWithUniformSpacingProducesNoTaper() throws
    {
        guard let context = makeContext() else { return }

        let points: ContiguousArray<simd_float3> = [
            simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(2, 0, 0), simd_float3(3, 0, 0),
        ]
        let geometry = tessellate(context: context, points: points, width: 1.0, speedWidthAmount: 1.0)

        for i in 0 ..< geometry.vertexCount
        {
            let widthScale = geometry.custom0(at: i).y
            #expect(widthScale.isFinite)
            #expect(abs(widthScale - 1.0) < 1e-4)
        }
    }

    @Test func roundCapsAreFrontFacingAtBothEnds() throws
    {
        guard let context = makeContext() else { return }

        let referenceNormal = simd_float3(0, 0, 1)
        let points: ContiguousArray<simd_float3> = [simd_float3(0, 0, 0), simd_float3(1, 0, 0)]

        #expect(allTrianglesFrontFacing(tessellate(context: context, points: points, capStyle: .round, roundResolution: 6), referenceNormal: referenceNormal))
    }

    @Test func defaultColorIsOpaqueWhiteWhenUnconnected() throws
    {
        guard let context = makeContext() else { return }

        let points: ContiguousArray<simd_float3> = [simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(1, 1, 0)]
        let geometry = tessellate(context: context, points: points, joinStyle: .bevel, capStyle: .round)

        for i in 0 ..< geometry.vertexCount
        {
            #expect(simd_length(geometry.color(at: i) - simd_float4(1, 1, 1, 1)) < 1e-5)
        }
    }

    @Test func colorsPropagateToEveryVertexAtEachPoint() throws
    {
        guard let context = makeContext() else { return }

        // A bevel join at P1 emits several vertices there (two rails + hub);
        // every one of them must carry P1's color, not just the rail vertices.
        let points: ContiguousArray<simd_float3> = [simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(1, 1, 0)]
        let red = simd_float4(1, 0, 0, 1)
        let green = simd_float4(0, 1, 0, 1)
        let blue = simd_float4(0, 0, 1, 1)
        let geometry = tessellate(
            context: context, points: points, joinStyle: .bevel, capStyle: .butt,
            pointColors: [red, green, blue]
        )

        var colorsByCore: [SIMD3<Float>: Set<SIMD4<Float>>] = [:]
        for i in 0 ..< geometry.vertexCount
        {
            let core = geometry.custom1(at: i)
            colorsByCore[core, default: []].insert(geometry.color(at: i))
        }

        #expect(colorsByCore[simd_float3(0, 0, 0)] == [red])
        #expect(colorsByCore[simd_float3(1, 0, 0)] == [green])
        #expect(colorsByCore[simd_float3(1, 1, 0)] == [blue])
    }

    @Test func shorterColorArrayPadsWithLastColor() throws
    {
        guard let context = makeContext() else { return }

        let points: ContiguousArray<simd_float3> = [simd_float3(0, 0, 0), simd_float3(1, 0, 0), simd_float3(2, 0, 0)]
        let red = simd_float4(1, 0, 0, 1)
        let green = simd_float4(0, 1, 0, 1)
        let geometry = tessellate(context: context, points: points, pointColors: [red, green])

        var colorsByCore: [SIMD3<Float>: SIMD4<Float>] = [:]
        for i in 0 ..< geometry.vertexCount
        {
            colorsByCore[geometry.custom1(at: i)] = geometry.color(at: i)
        }

        #expect(colorsByCore[simd_float3(0, 0, 0)] == red)
        #expect(colorsByCore[simd_float3(1, 0, 0)] == green)
        #expect(colorsByCore[simd_float3(2, 0, 0)] == green) // padded from the last supplied color
    }
}
