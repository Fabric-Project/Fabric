//
//  MediaPipeHandLandmarkProjection.swift
//  Fabric
//

import Foundation
import simd

/// Decodes the hand landmark model's raw outputs (63 floats = 21 x,y,z in
/// crop pixels; presence; handedness; 63 world-landmark floats) and projects
/// screen-space landmarks back through the rotated crop rect into full-image
/// normalized coordinates. Ported from fasthands.pipeline.HandLandmarker.
/// _landmarks (TensorsToLandmarksCalculator + LandmarkProjectionCalculator +
/// WorldLandmarkProjectionCalculator), numerically validated against that
/// Python reference (and the real bundled MediaPipeHandLandmarks.mlpackage's
/// output on a real image) to float32 precision.
enum MediaPipeHandLandmarkProjection
{
    static let landmarkSize: Float = 224
    static let normalizeZ: Float = 0.4
    static let minHandPresenceConfidence: Float = 0.5

    struct Hand
    {
        /// x, y normalized full-image [0,1], top-left origin; z is relative
        /// (same units as x, scaled by the crop rect's width — not a
        /// separate normalized space).
        var landmarks: [simd_float3]
        /// Same layout, but hand-centered, real-world-scale (meters) — not
        /// projected through the crop rect (WorldLandmarkProjectionCalculator
        /// only derotates, since world landmarks are already metric).
        var worldLandmarks: [simd_float3]
        var handedness: String
        var handednessScore: Float
    }

    /// `landmarksRaw`/`worldLandmarksRaw` are the flat 63-float (21x3)
    /// outputs, in the model's own output order (x,y,z per landmark).
    /// Returns nil when presence is below threshold (ThresholdingCalculator)
    /// — matches the Python reference dropping the hand entirely rather
    /// than emitting a low-confidence result.
    static func project(
        landmarksRaw: [Float], worldLandmarksRaw: [Float], presence: Float, handednessRaw: Float,
        rect: (cx: Float, cy: Float, width: Float, height: Float, rotation: Float)
    ) -> Hand?
    {
        guard presence > minHandPresenceConfidence else { return nil }

        // TensorsToClassificationCalculator binary_classification:
        // label_items[0] = Right (score s), label_items[1] = Left (score 1-s).
        let label: String
        let handednessScore: Float
        if handednessRaw >= 0.5 { label = "Right"; handednessScore = handednessRaw }
        else { label = "Left"; handednessScore = 1 - handednessRaw }

        let sinA = sin(rect.rotation)
        let cosA = cos(rect.rotation)

        var landmarks: [simd_float3] = []
        landmarks.reserveCapacity(21)
        for index in 0..<21
        {
            let x = landmarksRaw[index * 3 + 0] / landmarkSize - 0.5
            let y = landmarksRaw[index * 3 + 1] / landmarkSize - 0.5
            let z = landmarksRaw[index * 3 + 2] / landmarkSize / normalizeZ

            let rotatedX = cosA * x - sinA * y
            let rotatedY = sinA * x + cosA * y

            landmarks.append(simd_float3(
                rotatedX * rect.width + rect.cx,
                rotatedY * rect.height + rect.cy,
                z * rect.width
            ))
        }

        var worldLandmarks: [simd_float3] = []
        worldLandmarks.reserveCapacity(21)
        for index in 0..<21
        {
            let x = worldLandmarksRaw[index * 3 + 0]
            let y = worldLandmarksRaw[index * 3 + 1]
            let z = worldLandmarksRaw[index * 3 + 2]
            worldLandmarks.append(simd_float3(cosA * x - sinA * y, sinA * x + cosA * y, z))
        }

        return Hand(landmarks: landmarks, worldLandmarks: worldLandmarks, handedness: label, handednessScore: handednessScore)
    }
}
