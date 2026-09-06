//
//  RTMPoseInference.swift
//  Fabric
//

import CoreImage
import CoreML
import Foundation
import Metal
import simd

/// Runs a converted RTMPose model against a caller-supplied region of
/// interest and decodes keypoints via SimCCDecoder. Pure function, no
/// stored state — HandPoseAnalysisNode, FacePoseAnalysisNode,
/// BodyPoseDetectionNode, and WholeBodyPoseDetectionNode call this directly
/// from execute() and each keep their own last-good cache.
///
/// Two backends, chosen per model identity:
/// - `.handPose`: a from-scratch MPSGraph port (CSPNeXt backbone + RTMCCHead),
///   run directly on GPU — no CoreML, no Vision. Built after profiling showed
///   CoreML's automatic compute-unit placement falling back to slow CPU
///   execution for this model's GAU attention head; the MPSGraph port
///   validated to float32 precision against the PyTorch reference and runs
///   in ~6ms/frame. See RTMPoseMPSGraph.swift.
/// - Everything else (face/body/wholebody): still CoreML via RTMModelCache,
///   fed a CVPixelBuffer straight into MLModel.prediction(from:) (no Vision —
///   see ANEInputBuffer.swift). Not yet ported to MPSGraph.
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
    static func run(image: FabricImage, regionOfInterest: simd_float4, modelIdentity: RTMModelCache.ModelIdentity, keypointCount: Int, ciContext: CIContext? = nil, device: MTLDevice, commandQueue: MTLCommandQueue? = nil) throws -> [simd_float2]
    {
        let modelInputSize = Self.inputSize(for: modelIdentity)

        let decodedInModelSpace: [(position: simd_float2, confidence: Float)]

        if modelIdentity == .handPose
        {
            guard let commandQueue = commandQueue ?? device.makeCommandQueue() else
            {
                throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create RTMPose command queue")
            }
            let mpsModel = try Self.handMPSGraphModel(commandQueue: commandQueue)
            let (simccXValues, simccYValues) = try mpsModel.run(
                image: image,
                regionOfInterest: regionOfInterest
            )
            decodedInModelSpace = SimCCDecoder.decodeAll(simccX: simccXValues, simccY: simccYValues, keypointCount: keypointCount)
        }
        else
        {
            guard let ciContext else { return [] }
            guard let pixelBuffer = ANEInputBuffer.cropAndScale(image: image, regionOfInterest: regionOfInterest, destSize: modelInputSize, ciContext: ciContext) else
            {
                return []
            }
            let mlModel = try RTMModelCache.shared.model(for: modelIdentity)
            let inputProvider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)])
            let outputProvider = try mlModel.prediction(from: inputProvider)

            guard
                let simccX = outputProvider.featureValue(for: "simcc_x")?.multiArrayValue,
                let simccY = outputProvider.featureValue(for: "simcc_y")?.multiArrayValue
            else
            {
                return []
            }

            decodedInModelSpace = SimCCDecoder.decodeAll(simccX: simccX, simccY: simccY, keypointCount: keypointCount)
        }

        return Self.remapToFullImage(decodedInModelSpace, regionOfInterest: regionOfInterest, modelInputSize: modelInputSize)
    }

    /// Asynchronous hand-pose path: kicks off GPU work via RTMPoseMPSGraph's
    /// `.encode()`/`submit()` without blocking the calling thread, decoding
    /// and remapping on completion once the GPU finishes — trading a one-
    /// frame-or-more result delay for removing the `waitUntilCompleted`
    /// pipeline bubble from `run()`. `completion` fires on an arbitrary
    /// (non-caller) thread; callers must synchronize their own state.
    /// Silently drops the frame (never calls `completion`) when an
    /// inference is already in flight, matching `run()`'s no-backlog,
    /// no-smoothing semantics.
    static func submitHandPose(image: FabricImage, regionOfInterest: simd_float4, keypointCount: Int, device: MTLDevice, commandQueue: MTLCommandQueue? = nil, completion: @escaping ([simd_float2]) -> Void) throws
    {
        guard let commandQueue = commandQueue ?? device.makeCommandQueue() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create RTMPose command queue")
        }
        let mpsModel = try Self.handMPSGraphModel(commandQueue: commandQueue)
        let modelInputSize = Self.inputSize(for: .handPose)

        try mpsModel.submit(image: image, regionOfInterest: regionOfInterest) { result in
            guard case .success(let simcc) = result else { return }
            let decoded = SimCCDecoder.decodeAll(simccX: simcc.simccX, simccY: simcc.simccY, keypointCount: keypointCount)
            completion(Self.remapToFullImage(decoded, regionOfInterest: regionOfInterest, modelInputSize: modelInputSize))
        }
    }

    /// `decoded.position` is in local model-input pixel space, top-left
    /// origin (row 0 = top of the crop) — standard image raster order.
    /// Flips to bottom-left (Vision's convention) then composes with the
    /// ROI rect (also bottom-left-origin, normalized to the full image) to
    /// land back in full-image Vision-normalized space.
    private static func remapToFullImage(_ decoded: [(position: simd_float2, confidence: Float)], regionOfInterest: simd_float4, modelInputSize: CGSize) -> [simd_float2]
    {
        decoded.map { decoded in
            let normalizedInROITopLeft = simd_float2(
                decoded.position.x / Float(modelInputSize.width),
                decoded.position.y / Float(modelInputSize.height)
            )
            let normalizedInROIBottomLeft = simd_float2(normalizedInROITopLeft.x, 1 - normalizedInROITopLeft.y)
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

    // MARK: - MPSGraph hand model (loaded once, reused)

    private static var cachedHandModel: RTMPoseMPSGraph?
    private static let handModelLock = NSLock()

    private static func handMPSGraphModel(commandQueue: MTLCommandQueue) throws -> RTMPoseMPSGraph
    {
        Self.handModelLock.lock()
        defer { Self.handModelLock.unlock() }

        if let existing = Self.cachedHandModel
        {
            return existing
        }

        guard
            let binaryURL = Bundle.module.url(forResource: "RTMPoseHandMedium_weights", withExtension: "bin", subdirectory: "Models/Pose"),
            let manifestURL = Bundle.module.url(forResource: "RTMPoseHandMedium_weights", withExtension: "json", subdirectory: "Models/Pose")
        else
        {
            throw RTMModelCache.RTMModelCacheError.resourceNotFound("RTMPoseHandMedium_weights")
        }

        let model = try RTMPoseMPSGraph(weightsBinaryURL: binaryURL, weightsManifestURL: manifestURL, commandQueue: commandQueue)
        Self.cachedHandModel = model
        return model
    }
}
