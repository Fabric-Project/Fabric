//
//  MediaPipeHandLandmarkNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import QuartzCore
import simd
import MPSMediaPipe

/// Runs MediaPipe's hand landmark model against a caller-supplied region +
/// rotation. Standalone comparison test against HandPoseAnalysisNode's
/// RTMPose-based pipeline — not wired into it. Wire MediaPipe Hand
/// Detection's Region/Rotation/Keypoints outputs into this node's matching
/// inputs.
///
/// For multiple hands (MediaPipe Hand Detection's Multi mode), this node's
/// own ports don't change — wire it inside an Iterator fed by Detection's
/// Regions/Rotations (Iterator Info + an Array Index Value node picking
/// Regions[i]/Rotations[i] per iteration; an Array Append/Queue node
/// collects each iteration's Landmarks back into an array). Running inside
/// an Iterator automatically forces synchronous inference and bypasses
/// smoothing for that execute() call — an Iterator re-executes this same
/// node instance N times
/// sequentially within one frame, so the async path's later-arriving
/// completion and the one shared smoothing filter would both apply to the
/// wrong subject's data.
public class MediaPipeHandLandmarkNode: Node
{
    override public class var name: String { "MediaPipe Hand Landmarks" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Runs MediaPipe's hand landmark model, via MPSGraph, against a region + rotation from MediaPipe Hand Detection (test/comparison path, separate from HandPoseAnalysisNode/RTMPose). Outputs the same 21-keypoint finger groupings as Hand Pose Analysis for side-by-side comparison." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to analyze for hand landmarks")),
            ("inputRegionOfInterest", NodePort<simd_float4>(name: "Region", kind: .Inlet, description: "Hand region as (x, y, width, height) normalized bottom-left-origin — wire in from MediaPipe Hand Detection's Region output. Defaults to the full frame when unconnected.")),
            ("inputRotation", NodePort<Float>(name: "Rotation", kind: .Inlet, description: "In-plane rotation in radians — wire in from MediaPipe Hand Detection's Rotation output. Defaults to 0 (no rotation) when unconnected.")),
            ("inputKeypoints", NodePort<ContiguousArray<simd_float2>>(name: "Keypoints", kind: .Inlet, description: "Detector keypoints, already in Fabric's unit coordinate space — wire in from MediaPipe Hand Detection's Keypoints output. Passed straight through to this node's own Keypoints output so a single downstream consumer can see both the detector's coarse keypoints and the refined landmarks. Empty when unconnected.")),
            ("inputEnableSmoothing", ParameterPort(parameter: BoolParameter("Smoothing", true, .toggle, "Temporally smooth landmarks with a One Euro filter. Disable to see the model's raw, unsmoothed output."))),

            ("outputThumb", NodePort<ContiguousArray<simd_float2>>(name: "Thumb", kind: .Outlet, description: "Thumb points ordered CMC, MP, IP, Tip in unit coordinates")),
            ("outputIndex", NodePort<ContiguousArray<simd_float2>>(name: "Index", kind: .Outlet, description: "Index finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputMiddle", NodePort<ContiguousArray<simd_float2>>(name: "Middle", kind: .Outlet, description: "Middle finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputRing", NodePort<ContiguousArray<simd_float2>>(name: "Ring", kind: .Outlet, description: "Ring finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputLittle", NodePort<ContiguousArray<simd_float2>>(name: "Little", kind: .Outlet, description: "Little finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputWrist", NodePort<simd_float2>(name: "Wrist", kind: .Outlet, description: "Position of wrist in unit coordinates")),
            ("outputLandmarks3D", NodePort<ContiguousArray<simd_float3>>(name: "Landmarks 3D", kind: .Outlet, description: "All 21 hand landmarks (MediaPipe's own HAND_CONNECTIONS order: 0=wrist, 1-4=thumb, 5-8=index, 9-12=middle, 13-16=ring, 17-20=little) including depth. Unlike the finger-group outputs, this is NOT remapped to Fabric's -1...1 unit space — x,y stay normalized [0,1] bottom-left-origin and z is MediaPipe's own relative depth (scaled like x, no aspect meaning) — the raw form a future geometry/transform node would need, matching MediaPipeFaceLandmarkNode's outputLandmarks3D convention exactly. Empty if nothing was detected.")),
            ("outputLandmarksScene", NodePort<ContiguousArray<simd_float3>>(name: "Landmarks (Scene Space)", kind: .Outlet, description: "All 21 hand landmarks (same HAND_CONNECTIONS order as Landmarks 3D) remapped into Fabric's unit coordinate space (-1...1 horizontally, -aspect...aspect vertically, matching the finger-group outputs), z scaled by the same factor as x. Unlike Landmarks 3D's raw per-model relative depth, this is directly comparable against MediaPipe Face/Pose Landmarks' own Landmarks (Scene Space) output, so all three can be composited in one 3D scene — not physically metric, just a consistent shared space. Empty if nothing was detected.")),
            ("outputKeypoints", NodePort<ContiguousArray<simd_float2>>(name: "Keypoints", kind: .Outlet, description: "Pass-through of this node's Keypoints inlet, unchanged")),
            ("outputTrackedRegionOfInterest", NodePort<simd_float4>(name: "Tracked Region", kind: .Outlet, description: "This frame's landmarks re-expressed as a region for tracking the same hand next frame, matching MediaPipe Hand Detection's Previous Region inlet. Sent as nil (not a stale rect) whenever this frame's presence gate fails.")),
            ("outputTrackedRotation", NodePort<Float>(name: "Tracked Rotation", kind: .Outlet, description: "Paired with Tracked Region — wire into MediaPipe Hand Detection's Previous Rotation inlet.")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputRegionOfInterest: NodePort<simd_float4> { port(named: "inputRegionOfInterest") }
    public var inputRotation: NodePort<Float> { port(named: "inputRotation") }
    public var inputKeypoints: NodePort<ContiguousArray<simd_float2>> { port(named: "inputKeypoints") }
    public var inputEnableSmoothing: ParameterPort<Bool> { port(named: "inputEnableSmoothing") }

    public var outputThumb: NodePort<ContiguousArray<simd_float2>> { port(named: "outputThumb") }
    public var outputIndex: NodePort<ContiguousArray<simd_float2>> { port(named: "outputIndex") }
    public var outputMiddle: NodePort<ContiguousArray<simd_float2>> { port(named: "outputMiddle") }
    public var outputRing: NodePort<ContiguousArray<simd_float2>> { port(named: "outputRing") }
    public var outputLittle: NodePort<ContiguousArray<simd_float2>> { port(named: "outputLittle") }
    public var outputWrist: NodePort<simd_float2> { port(named: "outputWrist") }
    public var outputLandmarks3D: NodePort<ContiguousArray<simd_float3>> { port(named: "outputLandmarks3D") }
    public var outputLandmarksScene: NodePort<ContiguousArray<simd_float3>> { port(named: "outputLandmarksScene") }
    public var outputKeypoints: NodePort<ContiguousArray<simd_float2>> { port(named: "outputKeypoints") }
    public var outputTrackedRegionOfInterest: NodePort<simd_float4> { port(named: "outputTrackedRegionOfInterest") }
    public var outputTrackedRotation: NodePort<Float> { port(named: "outputTrackedRotation") }

    private static let fullFrameRegion = simd_float4(0, 0, 1, 1)


    /// Not a port -- Fabric has no systemized protocol yet for per-node
    /// synchronous/asynchronous execution, so this stays a compile-time
    /// switch for development/comparison until that exists (Iterator use
    /// forces synchronous regardless -- see execute()'s insideIterator
    /// comment). Flip locally to test the bounded-GPU-wait path.
    private static let synchronousInference = false

    private var preprocessor: MediaPipeCropPreprocessor?

    /// GPU-resident destinations for MediaPipeMPSGraph.encode()'s output
    /// tensors -- .storageModeShared so the completion handler can read them
    /// back without a CPU round-trip through submit().
    private var outputBuffers: [MTLBuffer]?
    private var model: MediaPipeMPSGraph?
    private let landmarksSmoothingFilter = MediaPipeLandmarksSmoothingFilter(debugLabel: "Hand")

    private let lastLandmarksLock = NSLock()
    private var lastLandmarksStorage: [simd_float3] = []
    private var lastLandmarksTimestampStorage: CFTimeInterval = 0
    private var lastRegionStorage: simd_float4 = MediaPipeHandLandmarkNode.fullFrameRegion

    override public func enableExecution(renderer: GraphRenderer) throws
    {
        try self.prepareModel()
    }

    override public func disableExecution(renderer: GraphRenderer) throws
    {
        self.model = nil
        self.preprocessor = nil
        self.outputBuffers = nil
    }
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
    /// The region this frame's lastLandmarks were actually decoded against
    /// -- cached alongside lastLandmarks (same lock, same producer) so
    /// execute() can compute the smoothing filter's object-scale
    /// normalization without re-reading a possibly-since-changed inlet.
    private var lastRegion: simd_float4
    {
        get
        {
            self.lastLandmarksLock.lock()
            defer { self.lastLandmarksLock.unlock() }
            return self.lastRegionStorage
        }
        set
        {
            self.lastLandmarksLock.lock()
            self.lastRegionStorage = newValue
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
            let synchronous = insideIterator || Self.synchronousInference
            try? self.detectLandmarks(image: inputImage, region: region, rotation: rotation, commandBuffer: commandBuffer, synchronous: synchronous)
        }

        self.outputKeypoints.send(self.inputKeypoints.value ?? [])

        guard let inImage = self.inputImage.value else { return }

        guard self.lastLandmarks.isEmpty == false else
        {
            self.landmarksSmoothingFilter.reset()
            // Presence gate failed -- nil, not a stale rect, so Detection's
            // tracking bypass doesn't latch onto an old lock once the
            // subject is actually gone.
            self.outputTrackedRegionOfInterest.send(nil)
            self.outputTrackedRotation.send(nil)
            return
        }

        let smoothedLandmarks: [simd_float3]
        if (self.inputEnableSmoothing.value ?? true) && !insideIterator
        {
            let presentationSize = inImage.presentationSize
            let imageWidthPixels = Float(presentationSize.width)
            let imageHeightPixels = Float(presentationSize.height)
            let region = self.lastRegion
            let objectScalePixels = (region.z * imageWidthPixels + region.w * imageHeightPixels) / 2
            let timestampNanoseconds = Int64((self.lastLandmarksTimestamp * 1e9).rounded())
            smoothedLandmarks = self.landmarksSmoothingFilter.smooth(points: self.lastLandmarks, timestampNanoseconds: timestampNanoseconds, objectScalePixels: objectScalePixels, imageWidthPixels: imageWidthPixels, imageHeightPixels: imageHeightPixels)
        }
        else
        {
            self.landmarksSmoothingFilter.reset()
            smoothedLandmarks = self.lastLandmarks
        }

        let aspect = Float(inImage.presentationSize.height / inImage.presentationSize.width)

        self.outputThumb.send(self.unitPoints(from: smoothedLandmarks, at: MediaPipeHandLandmarkProjection.thumbIndices, aspect: aspect))
        self.outputIndex.send(self.unitPoints(from: smoothedLandmarks, at: MediaPipeHandLandmarkProjection.indexIndices, aspect: aspect))
        self.outputMiddle.send(self.unitPoints(from: smoothedLandmarks, at: MediaPipeHandLandmarkProjection.middleIndices, aspect: aspect))
        self.outputRing.send(self.unitPoints(from: smoothedLandmarks, at: MediaPipeHandLandmarkProjection.ringIndices, aspect: aspect))
        self.outputLittle.send(self.unitPoints(from: smoothedLandmarks, at: MediaPipeHandLandmarkProjection.littleIndices, aspect: aspect))

        if smoothedLandmarks.indices.contains(MediaPipeHandLandmarkProjection.wristIndex)
        {
            self.outputWrist.send(self.unitPoint(from: smoothedLandmarks[MediaPipeHandLandmarkProjection.wristIndex], aspect: aspect))
        }

        self.outputLandmarks3D.send(ContiguousArray(smoothedLandmarks))
        self.outputLandmarksScene.send(ContiguousArray(smoothedLandmarks.map { self.scenePoint(from: $0, aspect: aspect) }))

        if let tracked = MediaPipeHandLandmarkProjection.trackedRegion(from: self.lastLandmarks, presentationSize: inImage.presentationSize)
        {
            self.outputTrackedRegionOfInterest.send(tracked.region)
            self.outputTrackedRotation.send(tracked.rotation)
        }
        else
        {
            self.outputTrackedRegionOfInterest.send(nil)
            self.outputTrackedRotation.send(nil)
        }
    }

    private func outputBuffers(for model: MediaPipeMPSGraph) throws -> [MTLBuffer]
    {
        if let existing = self.outputBuffers { return existing }

        let buffers = try model.outputBufferLengths.map { length -> MTLBuffer in
            guard let buffer = self.context.device.makeBuffer(length: length, options: .storageModeShared) else
            {
                throw FabricError(.execution(.outOfMemory), severity: .recoverable, message: "Could not allocate MediaPipe hand landmark output buffer")
            }
            return buffer
        }
        self.outputBuffers = buffers
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
    private func detectLandmarks(image: FabricImage, region: simd_float4, rotation: Float, commandBuffer: MTLCommandBuffer, synchronous: Bool) throws
    {
        let startTime = Date()
        try self.prepareModel()
        guard let preprocessor = self.preprocessor, let model = self.model else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "MediaPipe hand landmark model is unavailable")
        }
        let outputBuffers = try self.outputBuffers(for: model)

        let center = simd_float2(region.x + region.z / 2, region.y + region.w / 2)
        let size = simd_float2(region.z, region.w)

        let targetBuffer: MTLCommandBuffer
        if synchronous
        {
            guard let dedicated = self.context.commandQueue.makeCommandBuffer() else
            {
                throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create synchronous MediaPipe hand landmark command buffer")
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
        // via the closure.
        func projectedLandmarks() -> [simd_float3]
        {
            let outputs = outputBuffers.map { buffer -> [Float] in
                let count = buffer.length / MemoryLayout<Float>.stride
                return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: Float.self), count: count))
            }
            return Self.projectLandmarks(outputs: outputs, center: center, size: size, rotation: rotation)
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
                print("MediaPipeHandLandmarkNode: landmark detection failed: \(error)")
                return
            }
            MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
            self.lastLandmarks = projectedLandmarks()
            self.lastRegion = region
        }
        else
        {
            // Keeps `image` (and its texture) out of GraphRendererTextureCache's
            // recycle pool until the GPU work reading it is verified done, not
            // just encoded.
            targetBuffer.addCompletedHandler { [weak self, image, model, preprocessor, inputBuffer] finishedBuffer in
                withExtendedLifetime((image, model, preprocessor, inputBuffer)) {}
                guard let self else { return }
                if let error = finishedBuffer.error
                {
                    print("MediaPipeHandLandmarkNode: landmark detection failed: \(error)")
                    return
                }
                MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
                self.lastLandmarks = projectedLandmarks()
                self.lastRegion = region
            }
        }
    }

    /// outputs = [landmarks(63), presence(1), handedness(1), world_landmarks(63)].
    private static func projectLandmarks(outputs: [[Float]], center: simd_float2, size: simd_float2, rotation: Float) -> [simd_float3]
    {
        guard outputs.count >= 4 else { return [] }
        let (landmarksRaw, presenceRaw, handednessRaw, worldRaw) = (outputs[0], outputs[1], outputs[2], outputs[3])

        let presence = presenceRaw.first ?? 0
        let handedness = handednessRaw.first ?? 0

        // `center` is bottom-left-origin; flip to top-left for the
        // projection math, then flip the result back below.
        guard let hand = MediaPipeHandLandmarkProjection.project(
            landmarksRaw: landmarksRaw,
            worldLandmarksRaw: worldRaw,
            presence: presence,
            handednessRaw: handedness,
            rect: (cx: center.x, cy: 1 - center.y, width: size.x, height: size.y, rotation: rotation)
        ) else
        {
            return []
        }

        return hand.landmarks.map { simd_float3($0.x, 1 - $0.y, $0.z) }
    }

    private static func mpsGraphModel(commandQueue: MTLCommandQueue) throws -> MediaPipeMPSGraph
    {
        try MediaPipeSharedModels.model(named: MediaPipeHandLandmarkProjection.resourcePrefix, inputWidth: Int(MediaPipeHandLandmarkProjection.landmarkSize), inputHeight: Int(MediaPipeHandLandmarkProjection.landmarkSize), commandQueue: commandQueue)
    }

    private func prepareModel() throws
    {
        guard self.model == nil else { return }
        let model = try Self.mpsGraphModel(commandQueue: self.context.commandQueue)
        self.preprocessor = try MediaPipeCropPreprocessor(
            device: self.context.device,
            outputWidth: Int(MediaPipeHandLandmarkProjection.landmarkSize),
            outputHeight: Int(MediaPipeHandLandmarkProjection.landmarkSize)
        )
        self.outputBuffers = nil
        _ = try self.outputBuffers(for: model)
        self.model = model
    }

    private func unitPoints(from landmarks: [simd_float3], at indices: [Int], aspect: Float) -> ContiguousArray<simd_float2>
    {
        var points = ContiguousArray<simd_float2>()
        points.reserveCapacity(indices.count)

        for index in indices where landmarks.indices.contains(index)
        {
            points.append(self.unitPoint(from: landmarks[index], aspect: aspect))
        }

        return points
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
    /// constant (see MediaPipeHandLandmarkProjection.normalizeZ).
    private func scenePoint(from landmark: simd_float3, aspect: Float) -> simd_float3
    {
        simd_float3(remap(landmark.x, 0.0, 1.0, -1.0, 1.0),
                    remap(landmark.y, 0.0, 1.0, -aspect, aspect),
                    landmark.z * 2)
    }
}
