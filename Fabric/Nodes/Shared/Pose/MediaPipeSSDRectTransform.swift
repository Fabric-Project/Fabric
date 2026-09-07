//
//  MediaPipeSSDRectTransform.swift
//  Fabric
//

import Foundation

/// Projects a "Blaze"-family SSD detection from the detector's letterboxed
/// tensor space into full-image space, then derives the rotated square ROI
/// fed to the corresponding landmark model (DetectionsToRectsCalculator +
/// RectTransformationCalculator). Shared by BlazePalm (hand) and BlazeFace,
/// which use this exact calculator pair with different rotation keypoints/
/// target angle/scale/shift.
///
/// BlazePalm: rotation keypoints (wrist=0, middleMCP=2), target 90 (a real
/// MediaPipe proto quirk — see MediaPipeSSDDetectorDecoder.computeRotation's
/// doc comment), scale 2.6, shift_y -0.5. Ported from and validated against
/// fasthands.pipeline.letterbox_projection/project_detection/
/// HandLandmarker._detect_rects (a validated third-party port) to float32
/// precision on the real bundled MediaPipeHandDetector model's output on a
/// real image.
///
/// BlazeFace: rotation keypoints (leftEye=0, rightEye=1), target 0, scale
/// 1.5 (both axes), no shift — confirmed directly against
/// mediapipe/modules/face_landmark/face_detection_front_detection_to_roi.pbtxt.
/// Unlike BlazePalm, this has no local third-party reference to check
/// against — derived from primary source and sanity-checked with hand-
/// computed cases (horizontal eyes -> 0 rotation, vertical eyes -> 90°),
/// not validated end-to-end against a real detected face.
enum MediaPipeSSDRectTransform
{
    /// DetectionProjectionCalculator's matrix for the full-image, non-
    /// rotated, keep-aspect-ratio letterbox ROI used for detection (side =
    /// max(imageWidth, imageHeight), centered) — maps tensor-space
    /// normalized coordinates into full-image normalized coordinates, both
    /// top-left origin.
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

    static func project(_ detection: MediaPipeSSDDetectorDecoder.Detection, imageWidth: Float, imageHeight: Float) -> ProjectedDetection
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
    /// rotation in radians (MediaPipeSSDDetectorDecoder.computeRotation's
    /// own convention). Fed directly to MediaPipeCropPreprocessor for the
    /// rotated crop. `rotationKeypoints` indexes into `detection.keypoints`
    /// (BlazePalm: (0,2) wrist->middleMCP; BlazeFace: (0,1) leftEye->
    /// rightEye). `rectShiftX`/`rectShiftY` default to 0 (BlazeFace has no
    /// shift; BlazePalm passes shiftY=-0.5, shiftX=0).
    static func rect(
        from detection: ProjectedDetection, imageWidth: Float, imageHeight: Float,
        rotationKeypoints: (start: Int, end: Int), targetAngleRadians: Float,
        rectScale: Float, rectShiftX: Float = 0, rectShiftY: Float = 0
    ) -> (cx: Float, cy: Float, width: Float, height: Float, rotation: Float)
    {
        var cx = detection.xmin + detection.width / 2
        var cy = detection.ymin + detection.height / 2
        let width = detection.width
        let height = detection.height

        let startPoint = (x: detection.keypoints[rotationKeypoints.start].x * imageWidth, y: detection.keypoints[rotationKeypoints.start].y * imageHeight)
        let endPoint = (x: detection.keypoints[rotationKeypoints.end].x * imageWidth, y: detection.keypoints[rotationKeypoints.end].y * imageHeight)
        let rotation = MediaPipeSSDDetectorDecoder.computeRotation(from: startPoint, to: endPoint, targetAngleRadians: targetAngleRadians)

        let sinA = sin(rotation)
        let cosA = cos(rotation)
        if rotation == 0
        {
            cx += width * rectShiftX
            cy += height * rectShiftY
        }
        else
        {
            let xShift = (imageWidth * width * rectShiftX * cosA - imageHeight * height * rectShiftY * sinA) / imageWidth
            let yShift = (imageWidth * width * rectShiftX * sinA + imageHeight * height * rectShiftY * cosA) / imageHeight
            cx += xShift
            cy += yShift
        }

        let longSide = max(width * imageWidth, height * imageHeight)
        let rectWidth = longSide / imageWidth * rectScale
        let rectHeight = longSide / imageHeight * rectScale

        return (cx: cx, cy: cy, width: rectWidth, height: rectHeight, rotation: rotation)
    }
}
