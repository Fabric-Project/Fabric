//
//  RTMModelCache.swift
//  Fabric
//

import CoreML
import Foundation

/// Loads and caches the bundled RTMDet/RTMPose CoreML models. Synchronous by
/// design: pose/detection nodes call this directly from execute() and block
/// until the model is ready, matching Fabric's pull-based, one-execute-per-
/// frame model. These models are small, always bundled (never downloaded),
/// and stay resident for the app's lifetime once loaded. No Vision
/// dependency — callers feed a CVPixelBuffer straight into
/// MLModel.prediction(from:) (see ANEInputBuffer.swift).
final class RTMModelCache
{
    static let shared = RTMModelCache()

    enum ModelIdentity: Hashable
    {
        case personDetector
        case handDetector
        case faceDetector
        case bodyPose(PoseModelTier)
        case facePose(PoseModelTier)
        case handPose
        case wholeBodyPose

        /// The .mlpackage's base filename under Models/Pose, sans extension.
        var resourceName: String
        {
            switch self
            {
            case .personDetector: return "RTMDetPerson"
            case .handDetector: return "RTMDetHand"
            case .faceDetector: return "RTMDetFace"
            case .bodyPose(let tier): return "RTMPoseBody\(tier.rawValue)"
            case .facePose(let tier): return "RTMPoseFace\(tier.rawValue)"
            case .handPose: return "RTMPoseHandMedium"
            case .wholeBodyPose: return "RTMPoseWholeBodyMedium"
            }
        }
    }

    enum RTMModelCacheError: Error, LocalizedError
    {
        case resourceNotFound(String)

        var errorDescription: String?
        {
            switch self
            {
            case .resourceNotFound(let name):
                return "Could not find \(name).mlpackage in Models/Pose. Run the conversion pipeline in Tools/ModelConversion/RTMPose and bundle its output before using this node."
            }
        }
    }

    private var loadedModels: [ModelIdentity: MLModel] = [:]
    private let lock = NSLock()

    func model(for identity: ModelIdentity) throws -> MLModel
    {
        self.lock.lock()
        defer { self.lock.unlock() }

        if let loaded = self.loadedModels[identity]
        {
            return loaded
        }

        let model = try Self.loadModel(named: identity.resourceName)
        self.loadedModels[identity] = model
        return model
    }

    private static func loadModel(named resourceName: String) throws -> MLModel
    {
        guard let packageURL = Bundle.module.url(forResource: resourceName, withExtension: "mlpackage", subdirectory: "Models/Pose") else
        {
            throw RTMModelCacheError.resourceNotFound(resourceName)
        }

        let compiledURL = try Self.compiledModelURL(for: packageURL)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        return try MLModel(contentsOf: compiledURL, configuration: configuration)
    }

    /// Compiles a .mlpackage to .mlmodelc on first use and caches the
    /// compiled result in the caches directory, keyed by the package's
    /// modification date, so relaunches skip recompilation. .mlmodelc is
    /// OS/architecture-specific, which is why it's compiled on-device here
    /// rather than checked into the repo.
    private static func compiledModelURL(for packageURL: URL) throws -> URL
    {
        let cachesDirectory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let compiledModelsDirectory = cachesDirectory.appending(path: "RTMPoseCompiledModels", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: compiledModelsDirectory, withIntermediateDirectories: true)

        let modificationDate = (try? FileManager.default.attributesOfItem(atPath: packageURL.path)[.modificationDate] as? Date) ?? nil
        let modificationStamp = modificationDate.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
        let compiledFileName = "\(packageURL.deletingPathExtension().lastPathComponent)-\(modificationStamp).mlmodelc"
        let cachedCompiledURL = compiledModelsDirectory.appending(path: compiledFileName)

        if FileManager.default.fileExists(atPath: cachedCompiledURL.path)
        {
            return cachedCompiledURL
        }

        let freshlyCompiledURL = try MLModel.compileModel(at: packageURL)
        if FileManager.default.fileExists(atPath: cachedCompiledURL.path)
        {
            try FileManager.default.removeItem(at: cachedCompiledURL)
        }
        try FileManager.default.moveItem(at: freshlyCompiledURL, to: cachedCompiledURL)
        return cachedCompiledURL
    }
}
