//
//  MediaPipeFaceLandmarkProjection.swift
//  Fabric
//

import Foundation
import simd

/// Decodes FaceMesh's raw outputs (1404 floats = 468 x,y,z; 1 face-presence
/// flag) and projects screen-space landmarks back through the rotated crop
/// rect into full-image normalized coordinates. Ported from mediapipe's
/// actual graph config (mediapipe/modules/face_landmark/
/// face_landmark_cpu.pbtxt, tensors_to_face_landmarks.pbtxt) — no local
/// third-party reference exists for this model (unlike
/// MediaPipeHandLandmarkProjection, which fasthands.pipeline already
/// validated), so this was derived directly from the calculator source and
/// sanity-checked with hand-computed cases, not validated end-to-end
/// against a real detected face.
///
/// Differs from the hand landmark model's decode in three confirmed ways:
/// `normalize_z` defaults to 1.0 here (TensorsToLandmarksCalculatorOptions'
/// own proto default — the hand model's config explicitly overrides it to
/// 0.4, FaceMesh's does not), presence needs an explicit sigmoid
/// (TensorsToFloatsCalculatorOptions.activation: SIGMOID in the graph,
/// applied outside the model itself — the hand port's third-party reference
/// reads hand presence raw, unsigmoided, which this deliberately does not
/// copy since there's no equivalent validated reference for face to check
/// that assumption against), and there is no handedness or world-landmark
/// equivalent at all for the base (non-attention) FaceMesh variant.
enum MediaPipeFaceLandmarkProjection
{
    static let landmarkSize: Float = 192
    static let normalizeZ: Float = 1.0
    static let minFacePresenceConfidence: Float = 0.5
    static let landmarkCount = 468

    struct Face
    {
        /// x, y normalized full-image [0,1], top-left origin; z is relative
        /// (same units as x, scaled by the crop rect's width).
        var landmarks: [simd_float3]
    }

    /// `landmarksRaw` is the flat 1404-float (468x3) output, `presenceRaw`
    /// the single raw (pre-sigmoid) face-presence logit. Returns nil when
    /// presence is below threshold (ThresholdingCalculator) — matches the
    /// official graph dropping the face entirely rather than emitting a
    /// low-confidence result.
    static func project(
        landmarksRaw: [Float], presenceRaw: Float,
        rect: (cx: Float, cy: Float, width: Float, height: Float, rotation: Float)
    ) -> Face?
    {
        let presence = Float(1.0 / (1.0 + exp(-Double(presenceRaw))))
        guard presence > minFacePresenceConfidence else { return nil }

        let sinA = sin(rect.rotation)
        let cosA = cos(rect.rotation)

        var landmarks: [simd_float3] = []
        landmarks.reserveCapacity(landmarkCount)
        for index in 0..<landmarkCount
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

        return Face(landmarks: landmarks)
    }
}
