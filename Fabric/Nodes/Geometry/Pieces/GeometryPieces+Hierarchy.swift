//
//  GeometryPieces+Hierarchy.swift
//  Fabric
//

import Satin
import simd

extension GeometryPieces
{
    /// Each piece's generation: how many parents it has above it. 0 for a top-level piece,
    /// its parent's plus one otherwise.
    var generations: [Int]
    {
        var generations = [Int](repeating: 0, count: count)
        // Parents come before their children, so a parent's generation is known first.
        for (piece, parentIndex) in parentIndices.enumerated() where parentIndex >= 0
        {
            generations[piece] = generations[parentIndex] + 1
        }
        return generations
    }

    /// One transform per piece, each composed with its ancestors': `parent's composed × own`, so
    /// a parent's motion carries its children. `transforms` holds model-space deltas from rest in
    /// piece order; missing entries are identity and extra entries are ignored.
    func composedTransforms(_ transforms: [simd_float4x4]) -> [simd_float4x4]
    {
        var composed = [simd_float4x4](repeating: matrix_identity_float4x4, count: count)
        // Parents come before their children, so a parent is composed first.
        for piece in 0 ..< count
        {
            let own = piece < transforms.count ? transforms[piece] : matrix_identity_float4x4
            let parentIndex = parentIndices[piece]
            composed[piece] = parentIndex >= 0 ? composed[parentIndex] * own : own
        }
        return composed
    }
}
