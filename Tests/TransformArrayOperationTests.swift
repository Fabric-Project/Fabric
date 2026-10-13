import Testing
import simd
@testable import Fabric

@Suite("Transform Array Operations")
struct TransformArrayOperationTests
{
    private func translation(_ offset: simd_float3) -> simd_float4x4
    {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = simd_float4(offset, 1)
        return matrix
    }

    private func isClose(_ a: simd_float4x4, _ b: simd_float4x4, tolerance: Float = 1e-5) -> Bool
    {
        let delta = a - b
        return [delta.columns.0, delta.columns.1, delta.columns.2, delta.columns.3].allSatisfy { simd_reduce_max(simd_abs($0)) < tolerance }
    }

    @Test("Multiply applies B first, then A, and pads the shorter array with identity")
    func multiplyOrderAndPadding()
    {
        let spin = simd_float4x4(simd_quatf(angle: .pi / 2, axis: simd_float3(0, 0, 1)))
        let move = translation(simd_float3(1, 0, 0))
        let result = TransformArrayMultiplyNode.multiplied([move, move], [spin])
        #expect(result.count == 2)
        // B (spin) first: the x axis turns to y, then moves by +x.
        let point = result[0] * simd_float4(1, 0, 0, 1)
        #expect(simd_distance(simd_make_float3(point), simd_float3(1, 1, 0)) < 1e-5)
        #expect(isClose(result[1], move))
    }

    @Test("Blend keeps rotations rigid halfway through a half turn")
    func blendStaysRigid()
    {
        let halfTurn = simd_float4x4(simd_quatf(angle: .pi * 0.999, axis: simd_float3(0, 1, 0)))
        let middle = TransformArrayBlendNode.blended([matrix_identity_float4x4], [halfTurn], factors: [0.5])[0]
        let basis = simd_float3x3(simd_make_float3(middle.columns.0), simd_make_float3(middle.columns.1), simd_make_float3(middle.columns.2))
        let gram = basis.transpose * basis
        #expect(isClose(simd_float4x4(simd_float4(gram.columns.0, 0), simd_float4(gram.columns.1, 0), simd_float4(gram.columns.2, 0), simd_float4(0, 0, 0, 1)), matrix_identity_float4x4, tolerance: 1e-4), "Still a rotation: no skew or shrink")
        let quarter = simd_float4x4(simd_quatf(angle: .pi * 0.4995, axis: simd_float3(0, 1, 0)))
        #expect(isClose(middle, quarter, tolerance: 1e-4))
    }

    @Test("Blend ends at A and B, and follows per-element factors")
    func blendEndsAndPerElementFactors()
    {
        let a = translation(simd_float3(0, 0, 0))
        let b = translation(simd_float3(2, 0, 0))
        #expect(isClose(TransformArrayBlendNode.blended([a], [b], factors: [0])[0], a))
        #expect(isClose(TransformArrayBlendNode.blended([a], [b], factors: [1])[0], b))
        let result = TransformArrayBlendNode.blended([a, a, a], [b, b, b], factors: [0, 0.5])
        #expect(isClose(result[0], a))
        #expect(isClose(result[1], translation(simd_float3(1, 0, 0))))
        #expect(isClose(result[2], translation(simd_float3(1, 0, 0))), "A missing factor repeats the last one")
    }

    @Test("Blend between mirrored transforms stays mirrored")
    func blendKeepsMirroring()
    {
        let mirror = simd_float4x4(diagonal: simd_float4(-1, 1, 1, 1))
        let turned = simd_float4x4(simd_quatf(angle: .pi / 2, axis: simd_float3(0, 1, 0))) * mirror
        let result = TransformArrayBlendNode.blended([mirror, mirror, mirror], [turned, turned, turned], factors: [0, 0.5, 1])
        #expect(result.allSatisfy { abs($0.determinant + 1) < 1e-4 }, "Handedness survives the whole blend")
        #expect(isClose(result[2], turned, tolerance: 1e-4))
    }

    @Test("Transform interpolation stays rigid instead of mixing columns")
    func transformInterpolationStaysRigid()
    {
        let quarterTurn = simd_float4x4(simd_quatf(angle: .pi / 2, axis: simd_float3(0, 0, 1)))
        guard case .Transform(let middle) = NumericValueOperations.interpolate(.Transform(matrix_identity_float4x4), .Transform(quarterTurn), t: 0.5, as: .Transform) else
        {
            Issue.record("Expected a Transform")
            return
        }
        let eighthTurn = simd_float4x4(simd_quatf(angle: .pi / 4, axis: simd_float3(0, 0, 1)))
        #expect(isClose(middle, eighthTurn, tolerance: 1e-4), "Mixing columns would shrink the axes to ~0.707")
    }
}
