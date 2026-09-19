//
//  MediaPipePoseLandmarkNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import QuartzCore
import simd
import MPSMediaPipe

/// Runs MediaPipe's BlazePose landmark model (33 points) against a
/// caller-supplied region + rotation. Standalone comparison path,
/// mirroring MediaPipeFaceLandmarkNode/MediaPipeHandLandmarkNode's
/// structure. Wire MediaPipe Pose Detection's Region/Rotation/Keypoints
/// outputs into this node's matching inputs.
///
/// Model tier (Lite/Full/Heavy) is a plain dropdown — switching it never
/// changes port shape, only accuracy/latency.
///
/// outputSegmentationMask is computed by the model every frame regardless
/// of whether it's wired up, so exposing it costs no extra inference.
/// outputLandmarks3D exposes depth; the model's separate world-landmarks
/// output is unused, out of scope.
///
/// For multiple bodies (MediaPipe Pose Detection's Multi mode), this
/// node's own ports don't change — wire it inside an Iterator fed by
/// Detection's Regions/Rotations (Iterator Info + an Array Index Value
/// node picking Regions[i]/Rotations[i] per iteration; an Array Append/
/// Queue node collects each iteration's Landmarks back into an array).
/// Running inside an Iterator automatically forces synchronous inference
/// and bypasses smoothing for that execute() call — an Iterator re-executes
/// this same node instance N times sequentially within one frame, so the
/// async path's later-arriving completion and the one shared smoothing
/// filter would both apply to the wrong subject's data.
public class MediaPipePoseLandmarkNode: Node
{
    override public class var name: String { "MediaPipe Pose Landmarks" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Runs MediaPipe's BlazePose landmark model (33 points), via MPSGraph, against a region + rotation from MediaPipe Pose Detection (test/comparison path)." }

    private typealias ModelTier = MediaPipePoseLandmarkProjection.ModelTier

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to analyze for pose landmarks")),
            ("inputRegionOfInterest", NodePort<simd_float4>(name: "Region", kind: .Inlet, description: "Body region as (x, y, width, height) normalized bottom-left-origin — wire in from MediaPipe Pose Detection's Region output. Defaults to the full frame when unconnected.")),
            ("inputRotation", NodePort<Float>(name: "Rotation", kind: .Inlet, description: "In-plane rotation in radians — wire in from MediaPipe Pose Detection's Rotation output. Defaults to 0 (no rotation) when unconnected.")),
            ("inputKeypoints", NodePort<ContiguousArray<simd_float2>>(name: "Keypoints", kind: .Inlet, description: "Detector keypoints, already in Fabric's unit coordinate space — wire in from MediaPipe Pose Detection's Keypoints output. Passed straight through to this node's own Keypoints output so a single downstream consumer can see both the detector's coarse keypoints and the refined landmarks. Empty when unconnected.")),
            ("inputModelTier", ParameterPort(parameter: StringParameter("Model Tier", ModelTier.lite.rawValue, ModelTier.allCases.map(\.rawValue), .dropdown, "BlazePose landmark model size — Lite is fastest, Heavy is most accurate"))),
            ("inputEnableSmoothing", ParameterPort(parameter: BoolParameter("Smoothing", true, .toggle, "Temporally smooth landmarks with a One Euro filter. Disable to see the model's raw, unsmoothed output."))),

            ("outputLandmarks", NodePort<ContiguousArray<simd_float2>>(name: "Landmarks", kind: .Outlet, description: "All 33 BlazePose landmarks (see mediapipe's own topology: 0 nose, 1-6 eyes, 7-8 ears, 9-10 mouth, 11-22 shoulders/elbows/wrists/hands, 23-32 hips/knees/ankles/feet), in unit coordinates")),
            ("outputLandmarks3D", NodePort<ContiguousArray<simd_float3>>(name: "Landmarks 3D", kind: .Outlet, description: "All 33 BlazePose landmarks including depth. Unlike Landmarks, this is NOT remapped to Fabric's -1...1 unit space — x,y stay normalized [0,1] bottom-left-origin and z is MediaPipe's own relative depth (scaled like x, no aspect meaning) — the raw form a future geometry/transform node would need, matching MediaPipeFaceLandmarkNode's outputLandmarks3D convention exactly. Empty if nothing was detected.")),
            ("outputLandmarksScene", NodePort<ContiguousArray<simd_float3>>(name: "Landmarks (Scene Space)", kind: .Outlet, description: "All 33 BlazePose landmarks (same order as Landmarks 3D) remapped into Fabric's unit coordinate space (-1...1 horizontally, -aspect...aspect vertically, matching Landmarks), z scaled by the same factor as x. Unlike Landmarks 3D's raw per-model relative depth, this is directly comparable against MediaPipe Face/Hand Landmarks' own Landmarks (Scene Space) output, so all three can be composited in one 3D scene — not physically metric, just a consistent shared space. Empty if nothing was detected.")),
            ("outputKeypoints", NodePort<ContiguousArray<simd_float2>>(name: "Keypoints", kind: .Outlet, description: "Pass-through of this node's Keypoints inlet, unchanged")),
            ("outputSegmentationMask", NodePort<FabricImage>(name: "Segmentation Mask", kind: .Outlet, description: "BlazePose's per-pixel person-segmentation confidence (sigmoid-activated), reprojected to full image space. Not temporally smoothed.")),
            ("outputTrackedRegionOfInterest", NodePort<simd_float4>(name: "Tracked Region", kind: .Outlet, description: "This frame's landmarks re-expressed as a region for tracking the same body next frame, matching MediaPipe Pose Detection's Previous Region inlet. Sent as nil (not a stale rect) whenever this frame's pose presence gate fails.")),
            ("outputTrackedRotation", NodePort<Float>(name: "Tracked Rotation", kind: .Outlet, description: "Paired with Tracked Region — wire into MediaPipe Pose Detection's Previous Rotation inlet.")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputRegionOfInterest: NodePort<simd_float4> { port(named: "inputRegionOfInterest") }
    public var inputRotation: NodePort<Float> { port(named: "inputRotation") }
    public var inputKeypoints: NodePort<ContiguousArray<simd_float2>> { port(named: "inputKeypoints") }
    public var inputModelTier: ParameterPort<String> { port(named: "inputModelTier") }
    public var inputEnableSmoothing: ParameterPort<Bool> { port(named: "inputEnableSmoothing") }

    public var outputLandmarks: NodePort<ContiguousArray<simd_float2>> { port(named: "outputLandmarks") }
    public var outputLandmarks3D: NodePort<ContiguousArray<simd_float3>> { port(named: "outputLandmarks3D") }
    public var outputLandmarksScene: NodePort<ContiguousArray<simd_float3>> { port(named: "outputLandmarksScene") }
    public var outputKeypoints: NodePort<ContiguousArray<simd_float2>> { port(named: "outputKeypoints") }
    public var outputSegmentationMask: NodePort<FabricImage> { port(named: "outputSegmentationMask") }
    public var outputTrackedRegionOfInterest: NodePort<simd_float4> { port(named: "outputTrackedRegionOfInterest") }
    public var outputTrackedRotation: NodePort<Float> { port(named: "outputTrackedRotation") }

    private static let fullFrameRegion = simd_float4(0, 0, 1, 1)

    private static var cachedModels: [ModelTier: MediaPipeMPSGraph] = [:]
    private static let modelLock = NSLock()

    /// Not a port -- Fabric has no systemized protocol yet for per-node
    /// synchronous/asynchronous execution, so this stays a compile-time
    /// switch for development/comparison until that exists (Iterator use
    /// forces synchronous regardless -- see execute()'s insideIterator
    /// comment). Flip locally to test the bounded-GPU-wait path.
    private static let synchronousInference = false

    private var preprocessor: MediaPipeCropPreprocessor?

    /// GPU-resident destinations for MediaPipeMPSGraph.encode()'s output
    /// tensors (landmarks, pose flag, segmentation) -- .storageModeShared so
    /// the completion handler can read them back without a CPU round-trip
    /// through submit(). Recreated when the active tier changes.
    private var outputBuffers: [MTLBuffer]?
    private var outputBuffersTier: ModelTier?
    private var segmentationMaskProjector: MediaPipeSegmentationMaskProjector?
    private let landmarksSmoothingFilter = MediaPipeLandmarksSmoothingFilter(debugLabel: "Pose")

    private let lastLandmarksLock = NSLock()
    private var lastLandmarksStorage: [simd_float3] = []
    private var lastLandmarksTimestampStorage: CFTimeInterval = 0
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
            self.lastLandmarksTimestampStorage = CACurrentMediaTime()
            self.lastLandmarksLock.unlock()
        }
    }
    /// Real wall-clock time lastLandmarks was last actually set (stamped in
    /// its setter above) -- NOT executionInfo.timing.time, which is the
    /// render loop's own per-frame cadence and can run at a different rate
    /// than genuinely new landmarks arrive under the async path. Feeding
    /// the smoothing filter the render tick's own clock would make its
    /// adaptive cutoff see a spurious near-zero-delta sample on every tick
    /// where lastLandmarks is stale, then overestimate velocity on the
    /// tick a real update lands (its dt would only span one tick instead
    /// of the true time since the last genuine change).
    private var lastLandmarksTimestamp: CFTimeInterval
    {
        self.lastLandmarksLock.lock()
        defer { self.lastLandmarksLock.unlock() }
        return self.lastLandmarksTimestampStorage
    }

    /// The 2 dedicated region-derivation points, written alongside
    /// lastLandmarks (same lock, same producer). Next frame's tracking region
    /// must be derived from these, not from lastLandmarks[0]/[1].
    private var lastAuxiliaryLandmarksStorage: [simd_float3] = []
    private var lastAuxiliaryLandmarks: [simd_float3]
    {
        get
        {
            self.lastLandmarksLock.lock()
            defer { self.lastLandmarksLock.unlock() }
            return self.lastAuxiliaryLandmarksStorage
        }
        set
        {
            self.lastLandmarksLock.lock()
            self.lastAuxiliaryLandmarksStorage = newValue
            self.lastLandmarksLock.unlock()
        }
    }

    /// The raw (pre-sigmoid) segmentation mask tensor plus the crop rect it
    /// was decoded against -- both written alongside lastLandmarks (same
    /// lock, since they're always produced together by the same inference
    /// pass) and consumed by execute() to reproject the mask into full-image
    /// space on the graph thread, where a renderer + command buffer are
    /// available.
    private var lastSegmentationMaskStorage: [Float] = []
    private var lastCropRectStorage: (center: simd_float2, size: simd_float2, rotation: Float) = (.zero, .zero, 0)
    private var lastSegmentationMask: (logits: [Float], rect: (center: simd_float2, size: simd_float2, rotation: Float))
    {
        get
        {
            self.lastLandmarksLock.lock()
            defer { self.lastLandmarksLock.unlock() }
            return (self.lastSegmentationMaskStorage, self.lastCropRectStorage)
        }
        set
        {
            self.lastLandmarksLock.lock()
            self.lastSegmentationMaskStorage = newValue.logits
            self.lastCropRectStorage = newValue.rect
            self.lastLandmarksLock.unlock()
        }
    }

    public override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        // Non-nil when a MediaPipe Detection node's Multi-mode Regions/
        // Rotations are being fed in one at a time via an Iterator (see
        // MediaPipeDetectionMode's header). An Iterator re-executes this
        // same node instance N times sequentially within one command
        // buffer/frame -- encoding onto the shared buffer async wouldn't
        // produce a result until the whole frame's buffer completes, long
        // after this iteration needs it to feed the next one, and the one
        // shared landmarksSmoothingFilter would blend across unrelated
        // subjects if left on. Force synchronous inference (see
        // detectLandmarks()'s `synchronous` parameter) and bypass smoothing
        // whenever inside an iterator.
        let insideIterator = executionInfo.iterationInfo != nil

        if self.inputImage.valueDidChange, let inputImage = self.inputImage.value
        {
            let region = self.inputRegionOfInterest.value ?? Self.fullFrameRegion
            let rotation = self.inputRotation.value ?? 0
            let tier = ModelTier.from(self.inputModelTier.value)
            let synchronous = insideIterator || Self.synchronousInference

            do { try self.detectLandmarks(image: inputImage, region: region, rotation: rotation, tier: tier, commandBuffer: commandBuffer, synchronous: synchronous) }
            catch { print("MediaPipePoseLandmarkNode: detectLandmarks failed: \(error)") }
        }

        self.outputKeypoints.send(self.inputKeypoints.value ?? [])

        guard let inImage = self.inputImage.value else { return }

        if self.lastLandmarks.isEmpty == false
        {
            // Smooth in the raw [0,1] bottom-left + z space lastLandmarks is
            // already in, then derive both outputs from the smoothed result
            // -- not smoothing post-unitPoint(), which would put x/y in
            // different, aspect-dependent ranges.
            let smoothedLandmarks: [simd_float3]
            if (self.inputEnableSmoothing.value ?? true) && !insideIterator
            {
                let presentationSize = inImage.presentationSize
                let imageWidthPixels = Float(presentationSize.width)
                let imageHeightPixels = Float(presentationSize.height)
                let cropRectSize = self.lastSegmentationMask.rect.size
                let objectScalePixels = (cropRectSize.x * imageWidthPixels + cropRectSize.y * imageHeightPixels) / 2
                let timestampNanoseconds = Int64((self.lastLandmarksTimestamp * 1e9).rounded())
                smoothedLandmarks = self.landmarksSmoothingFilter.smooth(points: self.lastLandmarks, timestampNanoseconds: timestampNanoseconds, objectScalePixels: objectScalePixels, imageWidthPixels: imageWidthPixels, imageHeightPixels: imageHeightPixels)
            }
            else
            {
                self.landmarksSmoothingFilter.reset()
                smoothedLandmarks = self.lastLandmarks
            }

            let aspect = Float(inImage.presentationSize.height / inImage.presentationSize.width)
            var points = ContiguousArray<simd_float2>()
            var scenePoints = ContiguousArray<simd_float3>()
            points.reserveCapacity(smoothedLandmarks.count)
            scenePoints.reserveCapacity(smoothedLandmarks.count)
            for landmark in smoothedLandmarks
            {
                points.append(self.unitPoint(from: landmark, aspect: aspect))
                scenePoints.append(self.scenePoint(from: landmark, aspect: aspect))
            }
            self.outputLandmarks.send(points)
            self.outputLandmarks3D.send(ContiguousArray(smoothedLandmarks))
            self.outputLandmarksScene.send(scenePoints)
        }
        else
        {
            self.landmarksSmoothingFilter.reset()
        }

        if let tracked = MediaPipePoseLandmarkProjection.trackedRegion(from: self.lastAuxiliaryLandmarks, presentationSize: inImage.presentationSize)
        {
            self.outputTrackedRegionOfInterest.send(tracked.region)
            self.outputTrackedRotation.send(tracked.rotation)
        }
        else
        {
            // Presence gate failed (or too few landmarks) -- nil, not a
            // stale rect, so Detection's tracking bypass doesn't latch onto
            // an old lock once the subject is actually gone.
            self.outputTrackedRegionOfInterest.send(nil)
            self.outputTrackedRotation.send(nil)
        }

        let (maskLogits, cropRect) = self.lastSegmentationMask
        if maskLogits.isEmpty == false
        {
            do
            {
                let projector = try self.segmentationMaskProjector ?? MediaPipeSegmentationMaskProjector(device: self.context.device, maskWidth: MediaPipePoseLandmarkProjection.maskSize, maskHeight: MediaPipePoseLandmarkProjection.maskSize)
                self.segmentationMaskProjector = projector

                let presentationSize = inImage.presentationSize
                let outImage = try renderer.newImage(withWidth: Int(presentationSize.width), height: Int(presentationSize.height))

                try projector.encode(
                    maskValues: maskLogits,
                    centerNormalizedBottomLeft: cropRect.center,
                    sizeNormalized: cropRect.size,
                    rotationRadians: cropRect.rotation,
                    destinationTexture: outImage.texture,
                    commandBuffer: commandBuffer
                )

                self.outputSegmentationMask.send(outImage)
            }
            catch { print("MediaPipePoseLandmarkNode: segmentation mask projection failed: \(error)") }
        }
    }

    private func outputBuffers(for tier: ModelTier, model: MediaPipeMPSGraph) throws -> [MTLBuffer]
    {
        if let existing = self.outputBuffers, self.outputBuffersTier == tier { return existing }

        let buffers = try model.outputBufferLengths.map { length -> MTLBuffer in
            guard let buffer = self.context.device.makeBuffer(length: length, options: .storageModeShared) else
            {
                throw FabricError(.execution(.outOfMemory), severity: .recoverable, message: "Could not allocate MediaPipe pose landmark output buffer")
            }
            return buffer
        }
        self.outputBuffers = buffers
        self.outputBuffersTier = tier
        return buffers
    }

    /// Encodes crop-and-normalize AND MPSGraph inference, one after the
    /// other, onto either Fabric's shared `commandBuffer` (async) or a
    /// dedicated one this call owns exclusively (synchronous) -- the same
    /// two encode() calls either way, never committed by this node when
    /// sharing Fabric's buffer (its owner, the render loop, commits it once
    /// at the end of the frame), committed and waited on immediately by
    /// this call when `synchronous` is true (always true inside an
    /// Iterator -- see execute()'s insideIterator comment). Silently drops
    /// the cycle (never updates lastLandmarks) if all maxFramesInFlight
    /// inference slots are already busy, matching MediaPipeMPSGraph
    /// .encode()'s and MediaPipeCropPreprocessor's own no-backlog semantics.
    private func detectLandmarks(image: FabricImage, region: simd_float4, rotation: Float, tier: ModelTier, commandBuffer: MTLCommandBuffer, synchronous: Bool) throws
    {
        let startTime = Date()
        let preprocessor = try self.preprocessor ?? MediaPipeCropPreprocessor(device: self.context.device, outputWidth: Int(MediaPipePoseLandmarkProjection.landmarkSize), outputHeight: Int(MediaPipePoseLandmarkProjection.landmarkSize))
        self.preprocessor = preprocessor

        let model = try Self.mpsGraphModel(for: tier, commandQueue: self.context.commandQueue)
        let outputBuffers = try self.outputBuffers(for: tier, model: model)

        let center = simd_float2(region.x + region.z / 2, region.y + region.w / 2)
        let size = simd_float2(region.z, region.w)

        let targetBuffer: MTLCommandBuffer
        if synchronous
        {
            guard let dedicated = self.context.commandQueue.makeCommandBuffer() else
            {
                throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create synchronous MediaPipe pose landmark command buffer")
            }
            targetBuffer = dedicated
        }
        else
        {
            targetBuffer = commandBuffer
        }

        let inputBuffer = try preprocessor.encode(
            texture: image.texture,
            textureTransform: image.textureTransform,
            centerNormalizedBottomLeft: center,
            sizeNormalized: size,
            rotationRadians: rotation,
            commandBuffer: targetBuffer
        )

        guard try model.encode(inputBuffer: inputBuffer, outputBuffers: outputBuffers, commandBuffer: targetBuffer, commit: synchronous) else
        {
            return
        }

        // Captures no `self` -- safe to call from inside a [weak self]
        // completion handler without accidentally keeping this node alive
        // via the closure. Returns values rather than assigning lastX
        // properties directly, so each call site assigns using its own
        // correctly-scoped `self` (the weakly-captured one in the async
        // branch) instead of this function silently capturing a strong
        // `self` from detectLandmarks()'s own invocation.
        func decodedResults() -> (landmarks: [simd_float3], auxiliaryLandmarks: [simd_float3], maskLogits: [Float])
        {
            let outputs = outputBuffers.map { buffer -> [Float] in
                let count = buffer.length / MemoryLayout<Float>.stride
                return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: Float.self), count: count))
            }
            let (landmarks, auxiliaryLandmarks) = Self.projectLandmarks(outputs: outputs, center: center, size: size, rotation: rotation)
            return (landmarks, auxiliaryLandmarks, outputs.count >= 3 ? outputs[2] : [])
        }

        if synchronous
        {
            // model.encode() above already committed targetBuffer itself
            // (commit: synchronous) -- never call .commit() again on the
            // raw buffer here; see encode()'s doc comment for why (it
            // crashed exactly this way for MediaPipeFaceDetectionNode).
            targetBuffer.waitUntilCompleted()
            if let error = targetBuffer.error
            {
                print("MediaPipePoseLandmarkNode: landmark detection failed: \(error)")
                return
            }
            MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
            let results = decodedResults()
            self.lastLandmarks = results.landmarks
            self.lastAuxiliaryLandmarks = results.auxiliaryLandmarks
            self.lastSegmentationMask = (results.maskLogits, (center: center, size: size, rotation: rotation))
        }
        else
        {
            // Keeps `image` (and its texture) out of GraphRendererTextureCache's
            // recycle pool until the GPU work reading it is verified done, not
            // just encoded.
            targetBuffer.addCompletedHandler { [weak self, image] finishedBuffer in
                withExtendedLifetime(image) {}
                guard let self else { return }
                if let error = finishedBuffer.error
                {
                    print("MediaPipePoseLandmarkNode: landmark detection failed: \(error)")
                    return
                }
                MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
                let results = decodedResults()
                self.lastLandmarks = results.landmarks
                self.lastAuxiliaryLandmarks = results.auxiliaryLandmarks
                self.lastSegmentationMask = (results.maskLogits, (center: center, size: size, rotation: rotation))
            }
        }
    }

    /// outputs = [landmarks(195), pose flag(1), segmentation(256x256),
    /// heatmap(64x64x39), world landmarks(117)]. Segmentation is pulled
    /// directly from `outputs` at the call sites, not through this function.
    private static func projectLandmarks(outputs: [[Float]], center: simd_float2, size: simd_float2, rotation: Float) -> (landmarks: [simd_float3], auxiliaryLandmarks: [simd_float3])
    {
        guard outputs.count >= 4 else { return ([], []) }
        let (landmarksRaw, presenceRaw, heatmapRaw) = (outputs[0], outputs[1], outputs[3])
        guard landmarksRaw.count == MediaPipePoseLandmarkProjection.decodedLandmarkCount * 5 else { return ([], []) }

        // Refine x,y for all 39 decoded points from the heatmap before
        // rotation/rect projection. z, visibility, presence pass through
        // untouched.
        var rawXY: [simd_float2] = []
        rawXY.reserveCapacity(MediaPipePoseLandmarkProjection.decodedLandmarkCount)
        for index in 0..<MediaPipePoseLandmarkProjection.decodedLandmarkCount
        {
            let base = index * 5
            rawXY.append(simd_float2(landmarksRaw[base] / MediaPipePoseLandmarkProjection.landmarkSize, landmarksRaw[base + 1] / MediaPipePoseLandmarkProjection.landmarkSize))
        }
        let refinedXY = MediaPipePoseHeatmapRefinement.refine(
            landmarks: rawXY, heatmap: heatmapRaw,
            heatmapWidth: MediaPipePoseLandmarkProjection.heatmapSize, heatmapHeight: MediaPipePoseLandmarkProjection.heatmapSize, channelCount: MediaPipePoseLandmarkProjection.decodedLandmarkCount
        )

        var refinedLandmarksRaw = landmarksRaw
        for index in 0..<MediaPipePoseLandmarkProjection.decodedLandmarkCount
        {
            let base = index * 5
            refinedLandmarksRaw[base] = refinedXY[index].x * MediaPipePoseLandmarkProjection.landmarkSize
            refinedLandmarksRaw[base + 1] = refinedXY[index].y * MediaPipePoseLandmarkProjection.landmarkSize
        }

        // `center` is bottom-left-origin; flip to top-left for the
        // projection math, then flip the result back below.
        guard let pose = MediaPipePoseLandmarkProjection.project(
            landmarksRaw: refinedLandmarksRaw,
            presenceRaw: presenceRaw.first ?? -Float.greatestFiniteMagnitude,
            rect: (cx: center.x, cy: 1 - center.y, width: size.x, height: size.y, rotation: rotation)
        ) else
        {
            return ([], [])
        }

        let flip = { (point: simd_float3) in simd_float3(point.x, 1 - point.y, point.z) }
        return (pose.landmarks.map(flip), pose.auxiliaryLandmarks.map(flip))
    }

    private static func mpsGraphModel(for tier: ModelTier, commandQueue: MTLCommandQueue) throws -> MediaPipeMPSGraph
    {
        Self.modelLock.lock()
        defer { Self.modelLock.unlock() }

        if let existing = Self.cachedModels[tier] { return existing }

        let model = try MediaPipeMPSGraph.loadBundled(
            named: tier.resourcePrefix,
            inputWidth: Int(MediaPipePoseLandmarkProjection.landmarkSize), inputHeight: Int(MediaPipePoseLandmarkProjection.landmarkSize),
            commandQueue: commandQueue
        )
        Self.cachedModels[tier] = model
        return model
    }

    /// `landmark` is normalized full-image, bottom-left origin.
    private func unitPoint(from landmark: simd_float3, aspect: Float) -> simd_float2
    {
        simd_float2(remap(landmark.x, 0.0, 1.0, -1.0, 1.0),
                    remap(landmark.y, 0.0, 1.0, -aspect, aspect))
    }

    /// Same x/y remap as unitPoint(); z has no [0,1]-domain start/end like
    /// x/y do (it's a relative, roughly-zero-centered depth), so only the
    /// same *scale factor* x's remap applies (2, from -1...1 spanning a
    /// [0,1] domain) carries over -- matching MediaPipe's own convention
    /// that z's magnitude is on the same scale as x. This is what makes
    /// Face/Hand/Pose Landmarks' scene-space output directly comparable,
    /// independent of each model's own per-model depth-normalization
    /// constant (see MediaPipePoseLandmarkProjection.normalizeZ).
    private func scenePoint(from landmark: simd_float3, aspect: Float) -> simd_float3
    {
        simd_float3(remap(landmark.x, 0.0, 1.0, -1.0, 1.0),
                    remap(landmark.y, 0.0, 1.0, -aspect, aspect),
                    landmark.z * 2)
    }
}
