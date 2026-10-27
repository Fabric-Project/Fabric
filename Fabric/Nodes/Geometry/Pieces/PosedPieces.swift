//
//  PosedPieces.swift
//  Fabric
//

import Satin
import simd

/// A geometry with pieces (text glyphs, the pieces of a cut) posed by Transform Pieces: it draws
/// the geometry's vertex buffers with its own joint palette, one matrix per piece, so several
/// poses of one geometry never overwrite one another and only the matrices reach the GPU when
/// the pose changes.
///
/// Transforms are model-space deltas from rest, one per piece in piece order, and each piece is
/// drawn with its ancestors' transforms composed onto its own (`GeometryPieces.composedTransforms`),
/// so a parent's motion carries its children. A short array leaves the remaining pieces at rest;
/// extra entries are ignored. Velocity is the palette's: a change keeps last frame's pose as the
/// previous one, and once a pose has been drawn and held, the palette settles it.
final class PosedPieces: PosedGeometry
{
    /// One per piece; takes effect on the next update.
    var transforms: [simd_float4x4]
    {
        didSet { transformsChanged = true }
    }

    private var transformsChanged = false

    /// `source` must have pieces; the palette has one joint per piece, of every generation.
    init(source: Geometry, transforms: [simd_float4x4])
    {
        self.transforms = transforms
        let jointPalette = JointPalette(jointCount: source.pieces?.count ?? 0)
        super.init(source: source, jointPalette: jointPalette)
        // A new pose is not motion: no velocity on its first frame.
        jointPalette.reset(matrices: composedTransforms)
    }

    /// The palette entries: each piece's transform composed with its ancestors'.
    private var composedTransforms: [simd_float4x4]
    {
        pieces?.composedTransforms(transforms) ?? transforms
    }

    /// Once per frame per mesh drawing this, after the palette settles: uploads changed
    /// transforms at most once, keeping last frame's pose as the previous one for velocity.
    override func updatePose()
    {
        guard transformsChanged else { return }
        transformsChanged = false
        jointPalette?.update(matrices: composedTransforms)
    }
}
