//
//  simd_quatf+Orientation.swift
//  Fabric
//

import simd

extension simd_quatf
{
    /// Orientation whose local +Z axis points along `direction` and whose local
    /// +Y aligns with `up` where possible. When `direction` is parallel to `up`,
    /// falls back to whichever world axis is most perpendicular to `direction`
    /// (which can cause an abrupt roll change at the boundary). Returns identity
    /// for a zero-length, NaN or Inf `direction`.
    @inline(__always)
    init(lookingAlong direction: simd_float3, up: simd_float3)
    {
        let lenSq = simd_length_squared(direction)
        // Reject zero-length, NaN and Inf (Inf would yield Inf/Inf = NaN below).
        guard lenSq.isFinite, lenSq > 1e-12 else {
            self = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            return
        }
        let forward = direction / sqrt(lenSq)

        let eps: Float = 1e-4
        let upLenSq = simd_length_squared(up)
        var upRef: simd_float3 = upLenSq > eps ? (up / sqrt(upLenSq)) : simd_float3(0, 0, 1)

        if abs(simd_dot(upRef, forward)) > 1 - eps {
            let candidates: [simd_float3] = [
                simd_float3(1, 0, 0),
                simd_float3(0, 1, 0),
                simd_float3(0, 0, 1),
            ]
            upRef = candidates.min(by: { abs(simd_dot($0, forward)) < abs(simd_dot($1, forward)) })!
        }

        let right = simd_normalize(simd_cross(upRef, forward))
        let newUp = simd_cross(forward, right)
        // simd_float3x3 initialiser takes columns — local +X, +Y, +Z in world.
        self = simd_quatf(simd_float3x3(right, newUp, forward)).normalized
    }

    /// Quaternion from Euler angles in degrees, composed X → Y → Z
    /// (pitch → yaw → roll).
    @inline(__always)
    init(eulerAnglesDegrees angles: simd_float3)
    {
        let r = angles * (Float.pi / 180.0)
        let qx = simd_quatf(angle: r.x, axis: simd_float3(1, 0, 0))
        let qy = simd_quatf(angle: r.y, axis: simd_float3(0, 1, 0))
        let qz = simd_quatf(angle: r.z, axis: simd_float3(0, 0, 1))
        self = (qx * qy * qz).normalized
    }

    /// Quaternion from an axis and an angle in degrees. The axis is normalized;
    /// a zero/degenerate axis yields identity.
    @inline(__always)
    init(axis: simd_float3, angleDegrees: Float)
    {
        guard simd_length_squared(axis) > 1e-12 else {
            self = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            return
        }
        self = simd_quatf(angle: angleDegrees * (Float.pi / 180.0), axis: simd_normalize(axis)).normalized
    }

    /// The up direction an "Up Orientation" quaternion encodes — its local +Z
    /// axis rotated into world space (identity → world +Z). A degenerate
    /// (zero / NaN / Inf) input falls back to +Z.
    @inline(__always)
    static func upDirection(from orientation: simd_float4) -> simd_float3
    {
        simd_quatf(safeVector: orientation).act(simd_float3(0, 0, 1))
    }
}
