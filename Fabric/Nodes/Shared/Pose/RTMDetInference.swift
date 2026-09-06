//
//  RTMDetInference.swift
//  Fabric
//

import CoreImage
import CoreML
import Foundation
import simd

/// Runs a converted RTMDet model against the full frame and decodes boxes
/// via RTMDetDecoder. Pure function, no stored state — RegionDetectionNode
/// calls this directly from execute() and keeps its own last-good cache.
///
/// No Vision dependency: ANEInputBuffer does the scale-to-input-size
/// directly via CIContext, and the resulting CVPixelBuffer is fed straight
/// into MLModel.prediction(from:) — see ANEInputBuffer.swift for why
/// VNImageRequestHandler/VNCoreMLRequest were dropped.
///
/// Blocks the calling thread until inference completes, matching Fabric's
/// pull-based, one-execute-per-frame model.
enum RTMDetInference
{
    /// Standard mmdetection FPN strides, smallest-stride (largest feature
    /// map) first. RTMDet's typical 3-level head uses the first three;
    /// sliced to match however many levels the converted model actually
    /// reports. Confirm against the specific converted checkpoint.
    private static let defaultStrides = [8, 16, 32, 64]
    private static let fullFrameRegion = simd_float4(0, 0, 1, 1)

    static func run(image: FabricImage, targetClass: RTMModelCache.ModelIdentity, maxDetections: Int, ciContext: CIContext) throws -> [(rect: CGRect, confidence: Float)]
    {
        let modelInputSize = Self.inputSize(for: targetClass)

        guard let pixelBuffer = ANEInputBuffer.cropAndScale(image: image, regionOfInterest: Self.fullFrameRegion, destSize: modelInputSize, ciContext: ciContext) else
        {
            return []
        }

        let mlModel = try RTMModelCache.shared.model(for: targetClass)
        let inputProvider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)])
        let outputProvider = try mlModel.prediction(from: inputProvider)

        let scoreNames = outputProvider.featureNames
            .filter { $0.hasPrefix("scores_level") }
            .sorted { Self.levelIndex(from: $0) < Self.levelIndex(from: $1) }
        let boxNames = outputProvider.featureNames
            .filter { $0.hasPrefix("box_distances_level") }
            .sorted { Self.levelIndex(from: $0) < Self.levelIndex(from: $1) }

        let scores = scoreNames.compactMap { outputProvider.featureValue(for: $0)?.multiArrayValue }
        let boxDistances = boxNames.compactMap { outputProvider.featureValue(for: $0)?.multiArrayValue }
        guard scores.isEmpty == false, scores.count == boxDistances.count else { return [] }

        let strides = Array(Self.defaultStrides.prefix(scores.count))

        let decoded = RTMDetDecoder.decode(
            perLevelScores: scores,
            perLevelBoxDistances: boxDistances,
            strides: strides,
            inputSize: modelInputSize,
            maxDetections: maxDetections
        )

        return decoded.map { ($0.rect, $0.confidence) }
    }

    private static func levelIndex(from featureName: String) -> Int
    {
        guard let range = featureName.range(of: "level") else { return 0 }
        return Int(featureName[range.upperBound...]) ?? 0
    }

    /// Detector input resolutions — confirm against each converted
    /// checkpoint's actual training config.
    private static func inputSize(for identity: RTMModelCache.ModelIdentity) -> CGSize
    {
        switch identity
        {
        case .personDetector: return CGSize(width: 640, height: 640)
        case .handDetector, .faceDetector: return CGSize(width: 320, height: 320)
        default: return CGSize(width: 640, height: 640)
        }
    }
}
