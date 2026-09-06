//
//  SimCCDecoder.swift
//  Fabric
//

import CoreML
import Foundation
import simd

/// Decodes RTMPose's SimCC keypoint representation: two independent 1D
/// classification distributions per keypoint (simcc_x over `width *
/// splitRatio` bins, simcc_y over `height * splitRatio` bins) rather than a
/// 2D heatmap. Pure Swift, no CoreML/Vision request types — only the
/// MLMultiArray unpacking touches CoreML, so this is independently
/// unit-testable against synthetic arrays.
///
/// Confidence is produced for internal use only (jitter-smoothing / NMS-style
/// gating inside the pose nodes) — nothing in this codebase surfaces it on a
/// port.
enum SimCCDecoder
{
    /// Decodes one keypoint from its raw x/y SimCC distributions.
    /// `position` is in the model's own local input-pixel space
    /// (0...inputWidth, 0...inputHeight), not yet remapped into the ROI or
    /// into Fabric's unit coordinates — callers do that remap.
    static func decode(simccX: [Float], simccY: [Float], splitRatio: Float = 2.0) -> (position: simd_float2, confidence: Float)
    {
        let (xBin, xConfidence) = Self.argmaxWithParabolicRefinement(simccX)
        let (yBin, yConfidence) = Self.argmaxWithParabolicRefinement(simccY)

        let x = xBin / splitRatio
        let y = yBin / splitRatio
        let confidence = min(xConfidence, yConfidence)

        return (simd_float2(x, y), confidence)
    }

    /// Unpacks a batch of keypoints from CoreML's raw SimCC output tensors.
    /// Expects `simccX`/`simccY` shaped `[1, keypointCount, bins]` (row-major,
    /// one contiguous distribution per keypoint) — confirm this against the
    /// actual converted model's output shape before relying on it, since
    /// coremltools may order dimensions differently than the PyTorch source.
    static func decodeAll(simccX: MLMultiArray, simccY: MLMultiArray, keypointCount: Int, splitRatio: Float = 2.0) -> [(position: simd_float2, confidence: Float)]
    {
        Self.decodeAll(simccX: Self.floatValues(from: simccX), simccY: Self.floatValues(from: simccY), keypointCount: keypointCount, splitRatio: splitRatio)
    }

    /// Same as above, for callers that already have plain float arrays
    /// (e.g. an MPSGraph-based model's output) rather than an MLMultiArray.
    static func decodeAll(simccX: [Float], simccY: [Float], keypointCount: Int, splitRatio: Float = 2.0) -> [(position: simd_float2, confidence: Float)]
    {
        let xBinCount = simccX.count / max(keypointCount, 1)
        let yBinCount = simccY.count / max(keypointCount, 1)

        guard xBinCount > 0, yBinCount > 0,
              simccX.count == xBinCount * keypointCount,
              simccY.count == yBinCount * keypointCount
        else
        {
            return Array(repeating: (simd_float2(0, 0), Float(0)), count: keypointCount)
        }

        var results: [(position: simd_float2, confidence: Float)] = []
        results.reserveCapacity(keypointCount)

        for keypointIndex in 0..<keypointCount
        {
            let xRow = Array(simccX[(keypointIndex * xBinCount)..<((keypointIndex + 1) * xBinCount)])
            let yRow = Array(simccY[(keypointIndex * yBinCount)..<((keypointIndex + 1) * yBinCount)])
            results.append(Self.decode(simccX: xRow, simccY: yRow, splitRatio: splitRatio))
        }

        return results
    }

    /// `MLMultiArray.withUnsafeBufferPointer(ofType:)` hard-traps (not throws)
    /// if the requested type doesn't match the array's actual storage —
    /// mlprogram-converted models commonly output Float16, not Float32, so
    /// this must branch on the array's real `dataType` rather than assuming.
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

    /// Argmax with a DARK-style parabolic sub-bin refinement around the peak,
    /// plus a softmax confidence estimate for that peak. Plain Swift is fine
    /// at these array sizes (a few hundred floats) — no need for
    /// Accelerate/vDSP unless profiling says otherwise.
    private static func argmaxWithParabolicRefinement(_ distribution: [Float]) -> (bin: Float, confidence: Float)
    {
        guard distribution.isEmpty == false else { return (0, 0) }

        var bestIndex = 0
        var bestValue = distribution[0]
        for index in 1..<distribution.count
        {
            if distribution[index] > bestValue
            {
                bestValue = distribution[index]
                bestIndex = index
            }
        }

        let leftValue = bestIndex > 0 ? distribution[bestIndex - 1] : bestValue
        let rightValue = bestIndex < distribution.count - 1 ? distribution[bestIndex + 1] : bestValue

        var subBinOffset: Float = 0
        let curvature = leftValue - 2 * bestValue + rightValue
        if abs(curvature) > 1e-6
        {
            subBinOffset = max(-1, min(1, 0.5 * (leftValue - rightValue) / curvature))
        }

        // Softmax probability of the peak bin: exp(best - best) / sum(exp(v - best)).
        var sumExponentials: Float = 0
        for value in distribution
        {
            sumExponentials += exp(value - bestValue)
        }
        let confidence = sumExponentials > 0 ? 1 / sumExponentials : 0

        return (Float(bestIndex) + subBinOffset, confidence)
    }
}
