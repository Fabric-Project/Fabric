//
//  MediaPipeFaceLandmarkNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Runs MediaPipe's FaceMesh landmark model (468 points, non-attention
/// variant — no iris refinement) against a caller-supplied region +
/// rotation, via the shared generic MPSGraph TFLite interpreter (see
/// MediaPipeTFLiteMPSGraph.swift) — no CoreML. Standalone comparison path,
/// mirroring MediaPipeHandLandmarkNode's structure (same sync/async
/// toggle). Wire MediaPipe Face Detection's Region/Rotation outputs into
/// this node's matching inputs.
///
/// Unlike hand's 21 points (which map cleanly onto 5 named finger groups),
/// FaceMesh's 468-point topology has no equivalent small named grouping, so
/// this exposes the full landmark array rather than per-region ports.
public class MediaPipeFaceLandmarkNode: Node
{
    override public class var name: String { "MediaPipe Face Landmarks" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Runs MediaPipe's FaceMesh landmark model (468 points), via MPSGraph, against a region + rotation from MediaPipe Face Detection (test/comparison path, separate from FacePoseAnalysisNode/RTMPose)." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to analyze for face landmarks")),
            ("inputRegionOfInterest", NodePort<simd_float4>(name: "Region of Interest", kind: .Inlet, description: "Face region as (x, y, width, height) normalized bottom-left-origin — wire in from MediaPipe Face Detection's Region output. Defaults to the full frame when unconnected.")),
            ("inputRotation", NodePort<Float>(name: "Rotation", kind: .Inlet, description: "In-plane rotation in radians — wire in from MediaPipe Face Detection's Rotation output. Defaults to 0 (no rotation) when unconnected.")),

            ("outputLandmarks", NodePort<ContiguousArray<simd_float2>>(name: "Landmarks", kind: .Outlet, description: "All 468 FaceMesh landmarks, in FaceMesh's own canonical index order, in unit coordinates")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputRegionOfInterest: NodePort<simd_float4> { port(named: "inputRegionOfInterest") }
    public var inputRotation: NodePort<Float> { port(named: "inputRotation") }

    public var outputLandmarks: NodePort<ContiguousArray<simd_float2>> { port(named: "outputLandmarks") }

    private static let fullFrameRegion = simd_float4(0, 0, 1, 1)
    private static let inputSize = 192

    private static var cachedModel: MediaPipeTFLiteMPSGraph?
    private static let modelLock = NSLock()

    /// Not a Setting yet — a plain toggle while the async path is
    /// validated, mirroring MediaPipeHandLandmarkNode's own toggle.
    private static let useAsynchronousInference = true

    private var preprocessor: MediaPipeCropPreprocessor?

    private let lastLandmarksLock = NSLock()
    private var lastLandmarksStorage: [simd_float3] = []
    /// Backed by a lock because, under the async path, the GPU completion
    /// callback writes this from a thread other than execute()'s.
    private var lastLandmarks: [simd_float3]
    {
        get
        {
            self.lastLandmarksLock.lock()
            defer { self.lastLandmarksLock.unlock() }
            return self.lastLandmarksStorage
        }
        set
        {
            self.lastLandmarksLock.lock()
            self.lastLandmarksStorage = newValue
            self.lastLandmarksLock.unlock()
        }
    }

    public override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        if self.inputImage.valueDidChange, let inputImage = self.inputImage.value
        {
            let region = self.inputRegionOfInterest.value ?? Self.fullFrameRegion
            let rotation = self.inputRotation.value ?? 0

            if Self.useAsynchronousInference
            {
                do { try self.submitLandmarks(image: inputImage, region: region, rotation: rotation) }
                catch { print("MediaPipeFaceLandmarkNode: submitLandmarks failed: \(error)") }
            }
            else
            {
                do { self.lastLandmarks = try self.runLandmarks(image: inputImage, region: region, rotation: rotation) }
                catch { print("MediaPipeFaceLandmarkNode: runLandmarks failed: \(error)") }
            }
        }

        guard let inImage = self.inputImage.value else { return }
        guard self.lastLandmarks.isEmpty == false else { return }

        let aspect = Float(inImage.presentationSize.height / inImage.presentationSize.width)
        var points = ContiguousArray<simd_float2>()
        points.reserveCapacity(self.lastLandmarks.count)
        for landmark in self.lastLandmarks
        {
            points.append(self.unitPoint(from: landmark, aspect: aspect))
        }
        self.outputLandmarks.send(points)
    }

    private func runLandmarks(image: FabricImage, region: simd_float4, rotation: Float) throws -> [simd_float3]
    {
        let preprocessor = try self.preprocessor ?? MediaPipeCropPreprocessor(device: self.context.device, outputWidth: Self.inputSize, outputHeight: Self.inputSize)
        self.preprocessor = preprocessor

        let model = try Self.mpsGraphModel(commandQueue: self.context.commandQueue)

        let center = simd_float2(region.x + region.z / 2, region.y + region.w / 2)
        let size = simd_float2(region.z, region.w)

        let inputBuffer = try preprocessor.encode(
            image: image,
            centerNormalizedBottomLeft: center,
            sizeNormalized: size,
            rotationRadians: rotation,
            commandQueue: self.context.commandQueue
        )

        let outputs = model.run(inputBuffer: inputBuffer)
        return Self.projectLandmarks(outputs: outputs, center: center, size: size, rotation: rotation)
    }

    /// Async counterpart of runLandmarks(): encodes crop+inference onto one
    /// command buffer without waiting, updating lastLandmarks from the
    /// completion callback once the GPU finishes. Silently drops the frame
    /// (never updates lastLandmarks) if an inference is already in flight,
    /// matching runLandmarks()'s no-backlog semantics.
    private func submitLandmarks(image: FabricImage, region: simd_float4, rotation: Float) throws
    {
        let preprocessor = try self.preprocessor ?? MediaPipeCropPreprocessor(device: self.context.device, outputWidth: Self.inputSize, outputHeight: Self.inputSize)
        self.preprocessor = preprocessor

        let model = try Self.mpsGraphModel(commandQueue: self.context.commandQueue)

        let center = simd_float2(region.x + region.z / 2, region.y + region.w / 2)
        let size = simd_float2(region.z, region.w)

        guard let commandBuffer = self.context.commandQueue.makeCommandBuffer() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create asynchronous MediaPipe face landmark command buffer")
        }

        let inputBuffer = try preprocessor.encode(
            image: image,
            centerNormalizedBottomLeft: center,
            sizeNormalized: size,
            rotationRadians: rotation,
            commandBuffer: commandBuffer
        )

        model.submit(inputBuffer: inputBuffer, commandBuffer: commandBuffer) { [weak self] result in
            guard let self else { return }
            switch result
            {
            case .success(let outputs):
                self.lastLandmarks = Self.projectLandmarks(outputs: outputs, center: center, size: size, rotation: rotation)
            case .failure(let error):
                print("MediaPipeFaceLandmarkNode: async inference failed: \(error)")
            }
        }
    }

    /// Output order matches MediaPipeTFLiteMPSGraph's graph, which is
    /// TFLiteModule.forward()'s own return order, confirmed against
    /// mediapipe/modules/face_landmark/face_landmark_cpu.pbtxt's
    /// SplitTensorVectorCalculator ranges: [landmarks(1404), presence(1)].
    private static func projectLandmarks(outputs: [[Float]], center: simd_float2, size: simd_float2, rotation: Float) -> [simd_float3]
    {
        guard outputs.count >= 2 else { return [] }
        let (landmarksRaw, presenceRaw) = (outputs[0], outputs[1])

        // MediaPipeFaceLandmarkProjection's rect.cy is top-left-origin, but
        // `center` above is bottom-left-origin (the preprocessor's own
        // parameter flips it back internally) -- flip here for the
        // projection math, then flip the resulting landmarks' y back to
        // bottom-left-origin below, matching Fabric's other pose nodes.
        guard let face = MediaPipeFaceLandmarkProjection.project(
            landmarksRaw: landmarksRaw,
            presenceRaw: presenceRaw.first ?? -Float.greatestFiniteMagnitude,
            rect: (cx: center.x, cy: 1 - center.y, width: size.x, height: size.y, rotation: rotation)
        ) else
        {
            // Most likely cause when Region of Interest/Rotation are left
            // unconnected: the model is being fed the *whole* frame stretched
            // into a 192x192 square (no letterbox, no crop) rather than a
            // tight, upright face -- that's a well-out-of-distribution input
            // for FaceMesh, unlike the pose nodes elsewhere in Fabric that
            // tolerate a full-frame fallback reasonably. Wire in MediaPipe
            // Face Detection's Region/Rotation outputs and re-check.
            let presence = presenceRaw.first.map { 1.0 / (1.0 + exp(-Double($0))) } ?? 0
            print("MediaPipeFaceLandmarkNode: presence \(presence) <= threshold \(MediaPipeFaceLandmarkProjection.minFacePresenceConfidence) — dropping frame. If Region of Interest/Rotation are unconnected, wire in MediaPipe Face Detection first.")
            return []
        }

        return face.landmarks.map { simd_float3($0.x, 1 - $0.y, $0.z) }
    }

    private static func mpsGraphModel(commandQueue: MTLCommandQueue) throws -> MediaPipeTFLiteMPSGraph
    {
        Self.modelLock.lock()
        defer { Self.modelLock.unlock() }

        if let existing = Self.cachedModel { return existing }

        guard
            let binaryURL = Bundle.module.url(forResource: "MediaPipeFaceLandmarks_weights", withExtension: "bin", subdirectory: "Models/Pose"),
            let manifestURL = Bundle.module.url(forResource: "MediaPipeFaceLandmarks_weights", withExtension: "json", subdirectory: "Models/Pose"),
            let opsURL = Bundle.module.url(forResource: "MediaPipeFaceLandmarks_ops", withExtension: "json", subdirectory: "Models/Pose")
        else
        {
            throw FabricError(.execution(.failed), severity: .recoverable, message: "Could not find bundled MediaPipeFaceLandmarks graph resources")
        }

        let model = try MediaPipeTFLiteMPSGraph(
            weightsBinaryURL: binaryURL, weightsManifestURL: manifestURL, opsJSONURL: opsURL,
            inputWidth: Self.inputSize, inputHeight: Self.inputSize,
            commandQueue: commandQueue
        )
        Self.cachedModel = model
        return model
    }

    /// `landmarks` are normalized full-image, bottom-left origin already
    /// (MediaPipeFaceLandmarkProjection composes them against a
    /// bottom-left-origin center — see projectLandmarks above), matching
    /// the same space Fabric's other pose nodes' unitPoint expects.
    private func unitPoint(from landmark: simd_float3, aspect: Float) -> simd_float2
    {
        simd_float2(remap(landmark.x, 0.0, 1.0, -1.0, 1.0),
                    remap(landmark.y, 0.0, 1.0, -aspect, aspect))
    }
}
