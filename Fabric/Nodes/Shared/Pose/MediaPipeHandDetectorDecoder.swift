//
//  MediaPipeHandDetectorDecoder.swift
//  Fabric
//

import Foundation

/// Decodes BlazePalm's raw per-anchor output (TensorsToDetectionsCalculator)
/// and merges overlapping detections (NonMaxSuppressionCalculator,
/// algorithm=WEIGHTED — a score-weighted average of overlapping boxes, not a
/// greedy suppress like RTMDetDecoder's). Ported from
/// fasthands.pipeline.decode_detections/weighted_nms/iou, numerically
/// validated against that Python reference (and the real bundled
/// MediaPipeHandDetector.mlpackage's output on a real image) to float32
/// precision. Pure Swift, no CoreML dependency — independently unit-testable
/// against synthetic tensors, matching RTMDetDecoderTests' pattern.
enum MediaPipeHandDetectorDecoder
{
    static let numKeypoints = 7
    static let minDetectionConfidence: Float = 0.5
    static let nmsThreshold: Float = 0.3
    static let scoreClippingThreshold: Float = 100.0

    /// All coordinates normalized [0,1] in the detector's 192x192 tensor
    /// space, top-left origin (MediaPipe/OpenCV convention) — callers project
    /// into full-image space separately (see MediaPipeHandDetectionNode).
    struct Detection
    {
        var xmin: Float
        var ymin: Float
        var width: Float
        var height: Float
        /// 7 palm keypoints (x,y) — index 0 is the wrist, index 2 is the
        /// middle finger's MCP joint; both are used downstream to compute
        /// the hand's in-plane rotation.
        var keypoints: [(x: Float, y: Float)]
        var score: Float
    }

    /// `rawBoxes` is the flattened [2016,18] box-regression tensor (per
    /// anchor: 4 box values + 7 keypoints x,y), `rawScores` the flattened
    /// [2016,1] (really [2016]) classification tensor — both in the exact
    /// row-major order MLMultiArray/numpy already produce, straight off the
    /// model's two outputs, no MLMultiArray dependency here.
    static func decode(rawBoxes: [Float], rawScores: [Float], anchors: [(cx: Float, cy: Float, w: Float, h: Float)]) -> [Detection]
    {
        let scale = Float(MediaPipeHandAnchors.detectSize)
        var detections: [Detection] = []

        for anchorIndex in 0..<anchors.count
        {
            let logit = min(max(rawScores[anchorIndex], -scoreClippingThreshold), scoreClippingThreshold)
            // Sigmoid in float64 then rounded once to float32, matching the
            // Python reference's "correctly-rounded expf path" comment.
            let score = Float(1.0 / (1.0 + exp(-Double(logit))))
            guard score >= minDetectionConfidence else { continue }

            let anchor = anchors[anchorIndex]
            let base = anchorIndex * 18

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
    /// fasthands.pipeline.weighted_nms exactly, including iterating IoU
    /// against the full remaining set (the top detection always matches
    /// itself with IoU 1.0 and is folded into its own merge).
    static func weightedNonMaximumSuppression(_ detections: [Detection]) -> [Detection]
    {
        var remaining = detections.sorted { $0.score > $1.score }
        var merged: [Detection] = []

        while remaining.isEmpty == false
        {
            // Removing `top` unconditionally (rather than relying on its own
            // self-IoU exceeding nmsThreshold) guarantees `remaining` shrinks
            // every iteration — a zero-width/degenerate detection has a
            // self-IoU of 0 (see intersectionOverUnion's early-out), which
            // would otherwise leave it stuck in `remaining` forever.
            let top = remaining.removeFirst()
            let overlaps = remaining.map { intersectionOverUnion($0, top) }
            let candidates = [top] + zip(remaining, overlaps).filter { $0.1 > nmsThreshold }.map(\.0)
            remaining = zip(remaining, overlaps).filter { $0.1 <= nmsThreshold }.map(\.0)

            var result = top
            if candidates.isEmpty == false
            {
                var weightedXmin: Float = 0, weightedYmin: Float = 0, weightedXmax: Float = 0, weightedYmax: Float = 0
                var totalScore: Float = 0
                var keypointAccumulator = [(x: Float, y: Float)](repeating: (0, 0), count: numKeypoints)

                for candidate in candidates
                {
                    totalScore += candidate.score
                    weightedXmin += candidate.xmin * candidate.score
                    weightedYmin += candidate.ymin * candidate.score
                    weightedXmax += (candidate.xmin + candidate.width) * candidate.score
                    weightedYmax += (candidate.ymin + candidate.height) * candidate.score
                    for keypointIndex in 0..<numKeypoints
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

    /// DetectionsToRectsCalculator::ComputeRotation, reproduced exactly: the
    /// "90" is in RADIANS, not degrees — a MediaPipe proto quirk (the tasks
    /// graph sets rotation_vector_target_angle(90), and that field's units
    /// are radians; the _degrees variant is a separate proto field).
    static func computeRotation(wrist: (x: Float, y: Float), middleMCP: (x: Float, y: Float)) -> Float
    {
        let targetAngle: Float = 90.0
        let angle = targetAngle - atan2(-(middleMCP.y - wrist.y), middleMCP.x - wrist.x)
        return normalizeRadians(angle)
    }

    static func normalizeRadians(_ angle: Float) -> Float
    {
        angle - 2 * .pi * ((angle + .pi) / (2 * .pi)).rounded(.down)
    }
}
