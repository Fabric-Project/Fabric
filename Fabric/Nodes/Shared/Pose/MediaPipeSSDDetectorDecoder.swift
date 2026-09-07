//
//  MediaPipeSSDDetectorDecoder.swift
//  Fabric
//

import Foundation

/// Decodes a "Blaze"-family SSD detector's raw per-anchor output
/// (TensorsToDetectionsCalculator) and merges overlapping detections
/// (NonMaxSuppressionCalculator, algorithm=WEIGHTED — a score-weighted
/// average of overlapping boxes, not a greedy suppress like
/// RTMDetDecoder's). Shared by BlazePalm (hand) and BlazeFace, which use
/// this exact calculator pair with different `numKeypoints`/`detectSize`.
///
/// BlazePalm's box/keypoint decode ported from and validated against
/// fasthands.pipeline.decode_detections/weighted_nms/iou (a validated
/// third-party port) to float32 precision on the real bundled
/// MediaPipeHandDetector model's output on a real image. BlazeFace's decode
/// confirmed by reading mediapipe/calculators/tensor/
/// tensors_to_detections_calculator.cc directly: `reverse_output_order`
/// selects `XYWH` box-channel order, matching what BlazePalm already
/// assumed (BlazePalm's own — older — calculator has no such flag and uses
/// the equivalent fixed order), so the same decode formula applies to both
/// unmodified. Pure Swift, no CoreML dependency — independently
/// unit-testable against synthetic tensors, matching RTMDetDecoderTests'
/// pattern.
enum MediaPipeSSDDetectorDecoder
{
    static let minDetectionConfidence: Float = 0.5
    static let nmsThreshold: Float = 0.3
    static let scoreClippingThreshold: Float = 100.0

    /// All coordinates normalized [0,1] in the detector's tensor space,
    /// top-left origin (MediaPipe/OpenCV convention) — callers project into
    /// full-image space separately.
    struct Detection
    {
        var xmin: Float
        var ymin: Float
        var width: Float
        var height: Float
        var keypoints: [(x: Float, y: Float)]
        var score: Float
    }

    /// `rawBoxes` is the flattened `[anchors, 4 + numKeypoints*2]` box-
    /// regression tensor, `rawScores` the flattened `[anchors]`
    /// classification tensor — both in the exact row-major order
    /// MLMultiArray/numpy already produce, straight off the model's two
    /// outputs. `detectSize` is the square detector input size (192 for
    /// BlazePalm, 128 for BlazeFace) — box/keypoint regression values are
    /// scaled by it before being added to each anchor's center.
    static func decode(rawBoxes: [Float], rawScores: [Float], anchors: [(cx: Float, cy: Float, w: Float, h: Float)], numKeypoints: Int, detectSize: Int) -> [Detection]
    {
        let scale = Float(detectSize)
        let coordsPerAnchor = 4 + numKeypoints * 2
        var detections: [Detection] = []

        for anchorIndex in 0..<anchors.count
        {
            let logit = min(max(rawScores[anchorIndex], -scoreClippingThreshold), scoreClippingThreshold)
            // Sigmoid in float64 then rounded once to float32, matching the
            // Python reference's "correctly-rounded expf path" comment.
            let score = Float(1.0 / (1.0 + exp(-Double(logit))))
            guard score >= minDetectionConfidence else { continue }

            let anchor = anchors[anchorIndex]
            let base = anchorIndex * coordsPerAnchor

            let xc = rawBoxes[base + 0] / scale * anchor.w + anchor.cx
            let yc = rawBoxes[base + 1] / scale * anchor.h + anchor.cy
            let width = rawBoxes[base + 2] / scale * anchor.w
            let height = rawBoxes[base + 3] / scale * anchor.h
            let xmin = xc - width / 2
            let ymin = yc - height / 2

            var keypoints: [(x: Float, y: Float)] = []
            keypoints.reserveCapacity(numKeypoints)
            for keypointIndex in 0..<numKeypoints
            {
                let kx = rawBoxes[base + 4 + keypointIndex * 2] / scale * anchor.w + anchor.cx
                let ky = rawBoxes[base + 4 + keypointIndex * 2 + 1] / scale * anchor.h + anchor.cy
                keypoints.append((x: kx, y: ky))
            }

            detections.append(Detection(xmin: xmin, ymin: ymin, width: width, height: height, keypoints: keypoints, score: score))
        }

        return detections
    }

    static func intersectionOverUnion(_ a: Detection, _ b: Detection) -> Float
    {
        let xa = max(a.xmin, b.xmin), ya = max(a.ymin, b.ymin)
        let xb = min(a.xmin + a.width, b.xmin + b.width), yb = min(a.ymin + a.height, b.ymin + b.height)
        guard xb > xa, yb > ya else { return 0 }

        let intersection = (xb - xa) * (yb - ya)
        let union = a.width * a.height + b.width * b.height - intersection
        guard union > 0 else { return 0 }
        return intersection / union
    }

    /// WEIGHTED NMS: each retained detection is a score-weighted average of
    /// itself and every remaining detection whose IoU with it exceeds
    /// `nmsThreshold` — not a greedy suppress. Matches
    /// fasthands.pipeline.weighted_nms exactly (also confirmed as BlazeFace's
    /// own NonMaxSuppressionCalculator config: algorithm=WEIGHTED,
    /// min_suppression_threshold=0.3 — identical to BlazePalm's), including
    /// iterating IoU against the full remaining set. `top` is removed from
    /// `remaining` unconditionally (not via its own self-IoU exceeding
    /// `nmsThreshold`) so the loop provably terminates even for a
    /// degenerate (zero-width) detection, whose self-IoU is 0 — see
    /// intersectionOverUnion's early-out. (This is the fix for a real
    /// infinite-loop bug hit during BlazePalm bring-up.)
    static func weightedNonMaximumSuppression(_ detections: [Detection]) -> [Detection]
    {
        var remaining = detections.sorted { $0.score > $1.score }
        var merged: [Detection] = []

        while remaining.isEmpty == false
        {
            let top = remaining.removeFirst()
            let overlaps = remaining.map { intersectionOverUnion($0, top) }
            let candidates = [top] + zip(remaining, overlaps).filter { $0.1 > nmsThreshold }.map(\.0)
            remaining = zip(remaining, overlaps).filter { $0.1 <= nmsThreshold }.map(\.0)

            var result = top
            if candidates.isEmpty == false
            {
                var weightedXmin: Float = 0, weightedYmin: Float = 0, weightedXmax: Float = 0, weightedYmax: Float = 0
                var totalScore: Float = 0
                var keypointAccumulator = [(x: Float, y: Float)](repeating: (0, 0), count: top.keypoints.count)

                for candidate in candidates
                {
                    totalScore += candidate.score
                    weightedXmin += candidate.xmin * candidate.score
                    weightedYmin += candidate.ymin * candidate.score
                    weightedXmax += (candidate.xmin + candidate.width) * candidate.score
                    weightedYmax += (candidate.ymin + candidate.height) * candidate.score
                    for keypointIndex in 0..<top.keypoints.count
                    {
                        keypointAccumulator[keypointIndex].x += candidate.keypoints[keypointIndex].x * candidate.score
                        keypointAccumulator[keypointIndex].y += candidate.keypoints[keypointIndex].y * candidate.score
                    }
                }

                result.xmin = weightedXmin / totalScore
                result.ymin = weightedYmin / totalScore
                result.width = (weightedXmax / totalScore) - result.xmin
                result.height = (weightedYmax / totalScore) - result.ymin
                result.keypoints = keypointAccumulator.map { (x: $0.x / totalScore, y: $0.y / totalScore) }
            }

            merged.append(result)
        }

        return merged
    }

    /// DetectionsToRectsCalculator::ComputeRotation, generalized over which
    /// two keypoints define the rotation vector and the target angle:
    /// BlazePalm uses (wrist=0, middleMCP=2), target 90 — reproduced
    /// exactly including a real MediaPipe proto quirk (the tasks graph sets
    /// rotation_vector_target_angle(90), whose units are radians, not the
    /// separate _degrees field — so the effective target really is 90
    /// radians, confirmed against fasthands.pipeline's own comment to this
    /// effect). BlazeFace uses (leftEye=0, rightEye=1), target 0 (confirmed
    /// against mediapipe/modules/face_landmark/
    /// face_detection_front_detection_to_roi.pbtxt's
    /// rotation_vector_target_angle_degrees:0, i.e. 0 radians either way).
    static func computeRotation(from startPoint: (x: Float, y: Float), to endPoint: (x: Float, y: Float), targetAngleRadians: Float) -> Float
    {
        let angle = targetAngleRadians - atan2(-(endPoint.y - startPoint.y), endPoint.x - startPoint.x)
        return normalizeRadians(angle)
    }

    static func normalizeRadians(_ angle: Float) -> Float
    {
        angle - 2 * .pi * ((angle + .pi) / (2 * .pi)).rounded(.down)
    }
}
