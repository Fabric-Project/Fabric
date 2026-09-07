//
//  MediaPipeHandRectTransform.swift
//  Fabric
//

import Foundation

/// Projects a BlazePalm detection from the detector's 192x192 letterboxed
/// tensor space into full-image space, then derives the rotated square hand
/// ROI fed to the landmark model (DetectionsToRectsCalculator +
/// RectTransformationCalculator, scale 2.6 / shift_y -0.5 / square_long).
/// Ported from fasthands.pipeline.letterbox_projection/project_detection and
/// HandLandmarker._detect_rects, numerically validated against that Python
/// reference (and the real bundled MediaPipeHandDetector.mlpackage's output
/// on a real image) to float32 precision.
enum MediaPipeHandRectTransform
{
    static let rectScale: Float = 2.6
    static let rectShiftY: Float = -0.5

    /// DetectionProjectionCalculator's matrix for the full-image, non-
    /// rotated, keep-aspect-ratio letterbox ROI used for palm detection
    /// (side = max(imageWidth, imageHeight), centered) — maps 192x192
    /// tensor-space normalized coordinates into full-image normalized
    /// coordinates, both top-left origin.
    static func projectLetterbox(x: Float, y: Float, imageWidth: Float, imageHeight: Float) -> (x: Float, y: Float)
    {
        let side = max(imageWidth, imageHeight)
        let m0 = side / imageWidth
        let m3 = (-0.5 * side + 0.5 * imageWidth) / imageWidth
        let m5 = side / imageHeight
        let m7 = (-0.5 * side + 0.5 * imageHeight) / imageHeight
        return (x * m0 + m3, y * m5 + m7)
    }

    struct ProjectedDetection
    {
        var xmin: Float
        var ymin: Float
        var width: Float
        var height: Float
        var keypoints: [(x: Float, y: Float)]
        var score: Float
    }

    static func project(_ detection: MediaPipeHandDetectorDecoder.Detection, imageWidth: Float, imageHeight: Float) -> ProjectedDetection
    {
        let corners = [
            (detection.xmin, detection.ymin),
            (detection.xmin + detection.width, detection.ymin),
            (detection.xmin + detection.width, detection.ymin + detection.height),
            (detection.xmin, detection.ymin + detection.height),
        ]
        let projectedCorners = corners.map { projectLetterbox(x: $0.0, y: $0.1, imageWidth: imageWidth, imageHeight: imageHeight) }
        let xmin = projectedCorners.map(\.x).min()!
        let ymin = projectedCorners.map(\.y).min()!
        let xmax = projectedCorners.map(\.x).max()!
        let ymax = projectedCorners.map(\.y).max()!

        let projectedKeypoints = detection.keypoints.map { projectLetterbox(x: $0.x, y: $0.y, imageWidth: imageWidth, imageHeight: imageHeight) }

        return ProjectedDetection(xmin: xmin, ymin: ymin, width: xmax - xmin, height: ymax - ymin, keypoints: projectedKeypoints, score: detection.score)
    }

    /// (cx, cy, width, height) normalized full-image, top-left origin, plus
    /// rotation in radians (MediaPipe's own convention — see
    /// MediaPipeHandDetectorDecoder.computeRotation's doc comment). Fed
    /// directly to MediaPipeHandCropPreprocessor for the rotated crop.
    static func handRect(from detection: ProjectedDetection, imageWidth: Float, imageHeight: Float) -> (cx: Float, cy: Float, width: Float, height: Float, rotation: Float)
    {
        var cx = detection.xmin + detection.width / 2
        var cy = detection.ymin + detection.height / 2
        let width = detection.width
        let height = detection.height

        // kp[0] = wrist, kp[2] = middle finger MCP — fixed by BlazePalm's
        // keypoint ordering (7 palm points), needed in full-image pixels.
        let wrist = (x: detection.keypoints[0].x * imageWidth, y: detection.keypoints[0].y * imageHeight)
        let middleMCP = (x: detection.keypoints[2].x * imageWidth, y: detection.keypoints[2].y * imageHeight)
        let rotation = MediaPipeHandDetectorDecoder.computeRotation(wrist: wrist, middleMCP: middleMCP)

        let sinA = sin(rotation)
        let cosA = cos(rotation)
        if rotation == 0
        {
            cy += height * rectShiftY
        }
        else
        {
            let xShift = (-imageHeight * height * rectShiftY * sinA) / imageWidth
            let yShift = (imageHeight * height * rectShiftY * cosA) / imageHeight
            cx += xShift
            cy += yShift
        }

        let longSide = max(width * imageWidth, height * imageHeight)
        let rectWidth = longSide / imageWidth * rectScale
        let rectHeight = longSide / imageHeight * rectScale

        return (cx: cx, cy: cy, width: rectWidth, height: rectHeight, rotation: rotation)
    }
}
