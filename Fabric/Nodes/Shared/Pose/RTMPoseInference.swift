//
//  RTMPoseInference.swift
//  Fabric
//

import CoreImage
import CoreML
import CoreVideo
import Foundation
import simd

/// Runs a converted RTMPose model against a caller-supplied region of
/// interest and decodes keypoints via SimCCDecoder. Pure function, no
/// stored state — HandPoseAnalysisNode, FacePoseAnalysisNode,
/// BodyPoseDetectionNode, and WholeBodyPoseDetectionNode call this directly
/// from execute() and each keep their own last-good cache.
///
/// No Vision dependency: ANEInputBuffer does the crop+scale directly via
/// CIContext, and the resulting CVPixelBuffer is fed straight into
/// MLModel.prediction(from:) — see ANEInputBuffer.swift for why
/// VNImageRequestHandler/VNCoreMLRequest were dropped.
///
/// Blocks the calling thread until inference completes, matching Fabric's
/// pull-based, one-execute-per-frame model.
///
/// Returns points in the same Vision-normalized, full-image, bottom-left-
/// origin space `VNRecognizedPoint.x/y` used to occupy — so each pose
/// node's existing unit-coordinate conversion (HandPoseAnalysisNode.unitPoint,
/// FacePoseAnalysisNode.normalizedPointToUnits) works unchanged against
/// these points.
enum RTMPoseInference
{
    /// `regionOfInterest` is (x, y, width, height), normalized [0,1],
    /// bottom-left origin. Returns raw per-frame keypoints with no
    /// smoothing — temporal filtering, if wanted, is a downstream graph
    /// concern, not this node's job.
    static func run(image: FabricImage, regionOfInterest: simd_float4, modelIdentity: RTMModelCache.ModelIdentity, keypointCount: Int, ciContext: CIContext) throws -> [simd_float2]
    {
        let modelInputSize = Self.inputSize(for: modelIdentity)

        let mlModel: MLModel
        let inputProvider: MLFeatureProvider

        // Flip to swap just the input side for the cached IOSurface-backed
        // MLMultiArray path — everything below (prediction, decode, remap,
        // return) runs identically either way. Content is arbitrary garbage,
        // not a real crop, so output values are meaningless while this is
        // on; the point is profiling the real end-to-end call path, not
        // correctness. Requires RTMPoseHandMediumTensor.mlpackage
        // (convert_rtmpose.py --tensor-input) bundled in Models/Pose.
        if Self.useTensorInputExperiment, modelIdentity == .handPose
        {
            mlModel = try Self.experimentModel()
            inputProvider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(multiArray: Self.experimentMultiArray())])
        }
        else
        {
            guard let pixelBuffer = ANEInputBuffer.cropAndScale(image: image, regionOfInterest: regionOfInterest, destSize: modelInputSize, ciContext: ciContext) else
            {
                return []
            }
            mlModel = try RTMModelCache.shared.model(for: modelIdentity)
            inputProvider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)])
        }

        let outputProvider = try mlModel.prediction(from: inputProvider)

        guard
            let simccX = outputProvider.featureValue(for: "simcc_x")?.multiArrayValue,
            let simccY = outputProvider.featureValue(for: "simcc_y")?.multiArrayValue
        else
        {
            return []
        }

        let decodedInModelSpace = SimCCDecoder.decodeAll(simccX: simccX, simccY: simccY, keypointCount: keypointCount)

        return decodedInModelSpace.map { decoded in
            // decoded.position is in local model-input pixel space, top-left
            // origin (row 0 = top of the crop) — standard image raster order.
            let normalizedInROITopLeft = simd_float2(
                decoded.position.x / Float(modelInputSize.width),
                decoded.position.y / Float(modelInputSize.height)
            )

            // Flip to bottom-left origin within the ROI (Vision's convention,
            // which every pose node's own unit-coordinate conversion still
            // expects)...
            let normalizedInROIBottomLeft = simd_float2(normalizedInROITopLeft.x, 1 - normalizedInROITopLeft.y)

            // ...then compose with the ROI rect (also bottom-left-origin,
            // normalized to the full image) to land back in full-image
            // Vision-normalized space.
            return simd_float2(
                regionOfInterest.x + normalizedInROIBottomLeft.x * regionOfInterest.z,
                regionOfInterest.y + normalizedInROIBottomLeft.y * regionOfInterest.w
            )
        }
    }

    /// Pose model input resolutions (height matches the "H×W" convention
    /// used in the plan's model-selection table) — confirm against each
    /// converted checkpoint's actual training config.
    private static func inputSize(for identity: RTMModelCache.ModelIdentity) -> CGSize
    {
        switch identity
        {
        case .handPose: return CGSize(width: 256, height: 256)
        case .facePose: return CGSize(width: 256, height: 256)
        case .bodyPose: return CGSize(width: 192, height: 256)
        case .wholeBodyPose: return CGSize(width: 192, height: 256)
        default: return CGSize(width: 256, height: 256)
        }
    }

    // MARK: - IOSurface MLMultiArray copy-overhead experiment (temporary, in situ)

    static let useTensorInputExperiment = false

    private static let experimentShape: [NSNumber] = [1, 3, 256, 256]
    private static var cachedExperimentModel: MLModel?
    private static var cachedExperimentMultiArray: MLMultiArray?

    /// Loads once, caches, reuses. The only path Apple's docs explicitly
    /// promise skips MLE5BindInputBufferObjectByCopyingPixelBuffer's copy.
    private static func experimentModel() throws -> MLModel
    {
        if let existingModel = Self.cachedExperimentModel
        {
            return existingModel
        }

        guard let packageURL = Bundle.module.url(forResource: "RTMPoseHandMediumTensor", withExtension: "mlpackage", subdirectory: "Models/Pose") else
        {
            throw RTMModelCache.RTMModelCacheError.resourceNotFound("RTMPoseHandMediumTensor")
        }
        let compiledURL = try MLModel.compileModel(at: packageURL)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        let model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        Self.cachedExperimentModel = model
        return model
    }

    /// One-off IOSurface-backed MLMultiArray, built once and reused across
    /// every call. Content is arbitrary garbage (refreshed each call, not a
    /// real crop) — this exists to swap the input-binding mechanism only;
    /// everything downstream (prediction, decode, remap) is the real path.
    private static func experimentMultiArray() throws -> MLMultiArray
    {
        let multiArray: MLMultiArray
        if let existingArray = Self.cachedExperimentMultiArray
        {
            multiArray = existingArray
        }
        else
        {
            let dims = Self.experimentShape.map(\.intValue)
            let width = dims.last!
            let height = dims.reduce(1, *) / width

            let attributes: [CFString: Any] = [
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                kCVPixelBufferMetalCompatibilityKey: true,
            ]
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent16Half, attributes as CFDictionary, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else
            {
                throw RTMModelCache.RTMModelCacheError.resourceNotFound("RTMPoseHandMediumTensor IOSurface buffer")
            }

            multiArray = MLMultiArray(pixelBuffer: buffer, shape: Self.experimentShape)
            Self.cachedExperimentMultiArray = multiArray
        }

        let elementCount = Self.experimentShape.map(\.intValue).reduce(1, *)
        let pointer = multiArray.dataPointer.bindMemory(to: Float16.self, capacity: elementCount)
        let fillValue = Float16.random(in: 0...1)
        for index in 0..<elementCount { pointer[index] = fillValue }

        return multiArray
    }
}
