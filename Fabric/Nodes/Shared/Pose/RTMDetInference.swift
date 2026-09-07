//
//  RTMDetInference.swift
//  Fabric
//

import CoreML
import Foundation
import Metal
import simd

/// Runs a converted RTMDet model against the full frame and decodes boxes
/// via RTMDetDecoder. Pure function, no stored state — RegionDetectionNode
/// calls this directly from execute() and keeps its own last-good cache.
///
/// Runs on GPU via a from-scratch MPSGraph port (CSPNeXt backbone +
/// CSPNeXtPAFPN neck + RTMDetSepBNHead), not CoreML — see RTMDetMPSGraph.swift.
/// RTMDetDecoder's decode(perLevelScores:perLevelBoxDistances:...) predates
/// this and takes MLMultiArray, so this wraps the MPSGraph model's raw
/// per-level [Float] outputs into MLMultiArray rather than changing that
/// decoder's (still CoreML-shaped) public API.
///
/// Blocks the calling thread until inference completes, matching Fabric's
/// pull-based, one-execute-per-frame model.
enum RTMDetInference
{
    private static let fullFrameRegion = simd_float4(0, 0, 1, 1)

    static func run(image: FabricImage, targetClass: RTMModelCache.ModelIdentity, maxDetections: Int, device: MTLDevice, commandQueue: MTLCommandQueue? = nil) throws -> [(rect: CGRect, confidence: Float)]
    {
        guard let commandQueue = commandQueue ?? device.makeCommandQueue() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create RTMDet command queue")
        }

        let modelInputSize = Self.inputSize(for: targetClass)
        let mpsModel = try Self.detectorMPSGraphModel(for: targetClass, commandQueue: commandQueue)

        let (scores, boxDistances) = try mpsModel.run(image: image, regionOfInterest: Self.fullFrameRegion)

        let scoreArrays = try zip(scores, mpsModel.levelSizes).map { values, size in
            try Self.multiArray(from: values, shape: [1, 1, size.height, size.width])
        }
        let boxArrays = try zip(boxDistances, mpsModel.levelSizes).map { values, size in
            try Self.multiArray(from: values, shape: [1, 4, size.height, size.width])
        }

        let decoded = RTMDetDecoder.decode(
            perLevelScores: scoreArrays,
            perLevelBoxDistances: boxArrays,
            strides: RTMDetMPSGraph.strides,
            inputSize: modelInputSize,
            maxDetections: maxDetections
        )

        return decoded.map { ($0.rect, $0.confidence) }
    }

    private static func multiArray(from values: [Float], shape: [Int]) throws -> MLMultiArray
    {
        let multiArray = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        let pointer = multiArray.dataPointer.bindMemory(to: Float.self, capacity: values.count)
        values.withUnsafeBufferPointer { buffer in
            pointer.update(from: buffer.baseAddress!, count: values.count)
        }
        return multiArray
    }

    /// Detector input resolution — 320x320 for both the person and hand
    /// nano configs, resolved via mmengine.Config.fromfile against the
    /// actual configs, not assumed from checkpoint filenames. Face has no
    /// converted checkpoint yet — confirm before use.
    private static func inputSize(for identity: RTMModelCache.ModelIdentity) -> CGSize
    {
        CGSize(width: 320, height: 320)
    }

    // MARK: - MPSGraph detector models (one per identity, loaded once, reused)

    private static var cachedDetectorModels: [RTMModelCache.ModelIdentity: RTMDetMPSGraph] = [:]
    private static let detectorModelLock = NSLock()

    private static func detectorMPSGraphModel(for identity: RTMModelCache.ModelIdentity, commandQueue: MTLCommandQueue) throws -> RTMDetMPSGraph
    {
        Self.detectorModelLock.lock()
        defer { Self.detectorModelLock.unlock() }

        if let existing = Self.cachedDetectorModels[identity]
        {
            return existing
        }

        let resourceName = "\(identity.resourceName)_weights"
        guard
            let binaryURL = Bundle.module.url(forResource: resourceName, withExtension: "bin", subdirectory: "Models/Pose"),
            let manifestURL = Bundle.module.url(forResource: resourceName, withExtension: "json", subdirectory: "Models/Pose")
        else
        {
            throw RTMModelCache.RTMModelCacheError.resourceNotFound(resourceName)
        }

        let model = try RTMDetMPSGraph(weightsBinaryURL: binaryURL, weightsManifestURL: manifestURL, commandQueue: commandQueue)
        Self.cachedDetectorModels[identity] = model
        return model
    }
}
