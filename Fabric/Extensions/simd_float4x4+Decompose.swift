//
//  simd_float4x4+Decompose.swift
//  Fabric
//

import simd

extension simd_float4x4
{
    /// Decomposes an affine transform into translation, rotation and scale.
    ///
    /// Each basis column's length is its scale; the column normalized by that
    /// length recovers the rotation. A zero-length (degenerate / zero-scale)
    /// axis yields a 0 scale on that axis and falls back to the corresponding
    /// identity axis for the rotation, so the quaternion stays finite instead
    /// of dividing by zero and producing NaNs.
    var decomposedTRS: (translation: simd_float3, rotation: simd_quatf, scale: simd_float3)
    {
        let cx = simd_make_float3(columns.0)
        let cy = simd_make_float3(columns.1)
        let cz = simd_make_float3(columns.2)

        let scale = simd_float3(simd_length(cx), simd_length(cy), simd_length(cz))

        let rx = scale.x > 0 ? cx / scale.x : simd_float3(1, 0, 0)
        let ry = scale.y > 0 ? cy / scale.y : simd_float3(0, 1, 0)
        let rz = scale.z > 0 ? cz / scale.z : simd_float3(0, 0, 1)

        let rotation = simd_quatf(simd_float3x3(rx, ry, rz)).normalized
        let translation = simd_make_float3(columns.3)

        return (translation, rotation, scale)
    }
}
