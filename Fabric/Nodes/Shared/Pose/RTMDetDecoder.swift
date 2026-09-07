//
//  RTMDetDecoder.swift
//  Fabric
//

import CoreGraphics
import CoreML
import Foundation

/// Decodes RTMDet's anchor-free, FCOS/YOLOX-style detection head output:
/// per FPN level, a single-class score map and a 4-channel box-distance
/// regression map (distance from each grid cell's center to the box's
/// left/top/right/bottom edge, in that level's stride units). Pure Swift,
/// no CoreML/Vision request types beyond MLMultiArray unpacking — the box
/// math and NMS are independently unit-testable against synthetic tensors.
///
/// Every converted detector targets exactly one class (person, hand, or
/// face), so NMS here is single-class.
enum RTMDetDecoder
{
    /// `rect` is normalized to [0,1] in Vision's own bottom-left-origin
    /// convention — the same convention RegionDetectionNode's output ports
    /// use and VNCoreMLRequest.regionOfInterest expects, so callers can wire
    /// these straight through with no conversion.
    struct Detection
    {
        let rect: CGRect
        let confidence: Float
    }

    /// `perLevelScores[i]` and `perLevelBoxDistances[i]` must correspond to
    /// the same FPN level, decoded at `strides[i]`. Expected shapes (confirm
    /// against the actual converted model before relying on this):
    /// scores `[1, 1, H, W]` (single class, sigmoid probability — baked into
    /// the traced model by convert_rtmdet.py, since RTMDetSepBNHead.forward
    /// itself returns pre-sigmoid logits), box distances `[1, 4, H, W]`
    /// ordered (left, top, right, bottom), already multiplied by that
    /// level's stride (RTMDetSepBNHead.forward does `reg_dist * stride`
    /// internally when exp_on_reg=False, confirmed for the person/hand
    /// nano configs — re-check exp_on_reg for any other converted config).
    static func decode(
        perLevelScores: [MLMultiArray],
        perLevelBoxDistances: [MLMultiArray],
        strides: [Int],
        inputSize: CGSize,
        scoreThreshold: Float = 0.4,
        iouThreshold: Float = 0.5,
        maxDetections: Int = 16
    ) -> [Detection]
    {
        guard perLevelScores.count == perLevelBoxDistances.count, perLevelScores.count == strides.count else
        {
            return []
        }

        var candidates: [Detection] = []

        for levelIndex in 0..<perLevelScores.count
        {
            candidates.append(contentsOf: Self.decodeLevel(
                scores: perLevelScores[levelIndex],
                boxDistances: perLevelBoxDistances[levelIndex],
                stride: strides[levelIndex],
                inputSize: inputSize,
                scoreThreshold: scoreThreshold
            ))
        }

        return Self.nonMaximumSuppression(candidates, iouThreshold: iouThreshold, maxDetections: maxDetections)
    }

    private static func decodeLevel(scores: MLMultiArray, boxDistances: MLMultiArray, stride: Int, inputSize: CGSize, scoreThreshold: Float) -> [Detection]
    {
        let shape = scores.shape.map(\.intValue)
        guard shape.count >= 2 else { return [] }
        let height = shape[shape.count - 2]
        let width = shape[shape.count - 1]
        let planeSize = height * width

        guard boxDistances.count == planeSize * 4 else { return [] }

        var detections: [Detection] = []

        let scoreBuffer = Self.floatValues(from: scores)
        let distanceBuffer = Self.floatValues(from: boxDistances)

        for row in 0..<height
        {
            for column in 0..<width
            {
                let planeIndex = row * width + column
                let score = scoreBuffer[planeIndex]
                guard score >= scoreThreshold else { continue }

                // MlvlPointGenerator grid points are (column + offset) *
                // stride; both the person and hand nano configs set
                // anchor_generator.offset = 0 (not the library default of
                // 0.5) — re-check this for any other converted config.
                let centerX = Float(column) * Float(stride)
                let centerY = Float(row) * Float(stride)

                // Already in absolute pixel units — RTMDetSepBNHead.forward
                // multiplies by stride before returning (see decode(...)'s
                // doc comment), so no further scaling here.
                let left = distanceBuffer[0 * planeSize + planeIndex]
                let top = distanceBuffer[1 * planeSize + planeIndex]
                let right = distanceBuffer[2 * planeSize + planeIndex]
                let bottom = distanceBuffer[3 * planeSize + planeIndex]

                // Box in top-left-origin pixel space first...
                let x0 = centerX - left
                let y0 = centerY - top
                let x1 = centerX + right
                let y1 = centerY + bottom

                let normalizedX = x0 / Float(inputSize.width)
                let normalizedWidth = (x1 - x0) / Float(inputSize.width)
                // ...then flipped to bottom-left-origin normalized
                // coordinates (Vision's regionOfInterest convention).
                let normalizedYBottomLeft = 1 - (y1 / Float(inputSize.height))
                let normalizedHeight = (y1 - y0) / Float(inputSize.height)

                let rect = CGRect(
                    x: CGFloat(normalizedX),
                    y: CGFloat(normalizedYBottomLeft),
                    width: CGFloat(normalizedWidth),
                    height: CGFloat(normalizedHeight)
                )

                detections.append(Detection(rect: rect, confidence: score))
            }
        }

        return detections
    }

    /// `MLMultiArray.withUnsafeBufferPointer(ofType:)` hard-traps (not throws)
    /// if the requested type doesn't match the array's actual storage —
    /// mlprogram-converted models commonly output Float16, not Float32.
    private static func floatValues(from multiArray: MLMultiArray) -> [Float]
    {
        switch multiArray.dataType
        {
        case .float32:
            return multiArray.withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
        case .float16:
            return multiArray.withUnsafeBufferPointer(ofType: Float16.self) { $0.map(Float.init) }
        case .double:
            return multiArray.withUnsafeBufferPointer(ofType: Double.self) { $0.map(Float.init) }
        case .int32:
            return multiArray.withUnsafeBufferPointer(ofType: Int32.self) { $0.map(Float.init) }
        default:
            var values = [Float]()
            values.reserveCapacity(multiArray.count)
            for index in 0..<multiArray.count { values.append(multiArray[index].floatValue) }
            return values
        }
    }

    private static func nonMaximumSuppression(_ detections: [Detection], iouThreshold: Float, maxDetections: Int) -> [Detection]
    {
        var remaining = detections.sorted { $0.confidence > $1.confidence }
        var kept: [Detection] = []

        while remaining.isEmpty == false, kept.count < maxDetections
        {
            let best = remaining.removeFirst()
            kept.append(best)
            remaining.removeAll { Self.intersectionOverUnion($0.rect, best.rect) > iouThreshold }
        }

        return kept
    }

    private static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> Float
    {
        let intersection = a.intersection(b)
        guard intersection.isNull == false, intersection.width > 0, intersection.height > 0 else { return 0 }

        let intersectionArea = Float(intersection.width * intersection.height)
        let unionArea = Float(a.width * a.height + b.width * b.height) - intersectionArea

        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
