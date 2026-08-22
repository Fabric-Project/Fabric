//
//  simd_quatf+SafeVector.swift
//  Fabric
//

import simd

extension simd_quatf
{
    /// Unit quaternion from a raw (x, y, z, w) vector, falling back to identity
    /// for degenerate input (zero-length, NaN or Inf) so a bad value can't
    /// poison downstream orientations.
    @inline(__always)
    init(safeVector v: simd_float4)
    {
        let lenSq = simd_length_squared(v)
        if lenSq.isFinite, lenSq > 1e-12 {
            self = simd_quatf(vector: v).normalized
        } else {
            self = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        }
    }
}
