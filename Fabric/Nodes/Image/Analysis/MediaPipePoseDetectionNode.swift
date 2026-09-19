//
//  MediaPipePoseDetectionNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd
import MPSMediaPipe

/// Detects a body using MediaPipe's BlazePose detector. Standalone
/// comparison path, mirroring MediaPipeFaceDetectionNode/
/// MediaPipeHandDetectionNode's structure. Outputs a region (matching
/// RegionDetectionNode's own bottom-left-origin simd_float4 convention)
/// plus a separate rotation in radians — MediaPipePoseLandmarkNode
/// consumes both directly. Single model, no variant switch.
///
/// Single/Multi is a Settings choice (see MediaPipeDetectionMode) since it
/// reshapes this node's ports, not a runtime value:
///
/// Single mode tracks exactly one body and exposes the tracking fast path
/// — wire MediaPipe Pose Landmark's outputTrackedRegionOfInterest/
/// outputTrackedRotation back into this node's Previous Region/Previous
/// Rotation inputs to skip re-running the detector while tracking holds. A
/// nil or unconnected Previous Region falls through to running the detector
/// every frame. Redetect Interval forces a fresh detector run periodically
/// even while a previous region is present. This mirrors mediapipe's own
/// pose_landmark_cpu.pbtxt exactly, which is genuinely single-instance-only
/// (prev_pose_rect_from_landmarks is a singular NormalizedRect there too,
/// with no association/matching calculator at all).
///
/// Multi mode detects up to Max Detections bodies every frame (no tracking
/// fast path — mediapipe itself has no multi-person equivalent to port,
/// unlike hand/face) and exposes plural Regions/Rotations. Wire those into
/// an Iterator (with Iterator Info + an Array Index Value node picking
/// Regions[i]/Rotations[i] per iteration) feeding a single MediaPipe Pose
/// Landmark node inside — not a change to the Landmark node itself.
///
/// Keypoint semantics: 0 mid hip center, 1 size/rotation point (full
/// body), 2 mid shoulder center, 3 size/rotation point (upper body).
public class MediaPipePoseDetectionNode: StrategyNode
{
    override public class var name: String { "MediaPipe Pose Detection" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Detects a body using MediaPipe's BlazePose detector, run via MPSGraph (test/comparison path, separate from RegionDetectionNode/RTMDet). Single/Multi mode (Settings) picks between one tracked body with Previous Region/Rotation, or up to Max Detections bodies with plural Regions/Rotations." }

    override public class var strategyOptions: [any NodeStrategyOption] { MediaPipeDetectionMode.allCases }

    private static let allDynamicPortNames: Set<String> = [
        "inputPreviousRegionOfInterest", "inputPreviousRotation", "inputRedetectInterval",
        "outputRegionOfInterest", "outputRotation", "outputKeypoints",
        "inputMaxDetections", "outputRegionsOfInterest", "outputRotations",
    ]

    private static func dynamicPorts(for mode: MediaPipeDetectionMode) -> [(name: String, port: Port)]
    {
        switch mode
        {
        case .single:
            return [
                ("inputPreviousRegionOfInterest", NodePort<simd_float4>(name: "Previous Region", kind: .Inlet, description: "Optional tracking fast path — wire in MediaPipe Pose Landmark's Tracked Region output. When present (and the redetect interval hasn't elapsed), the detector model is skipped and this region is passed straight through. Leave unconnected for plain per-frame detection.")),
                ("inputPreviousRotation", NodePort<Float>(name: "Previous Rotation", kind: .Inlet, description: "Paired with Previous Region — wire in MediaPipe Pose Landmark's Tracked Rotation output.")),
                ("inputRedetectInterval", ParameterPort(parameter: IntParameter("Re-detect Every N Frames", Self.defaultRedetectInterval, 1, 240, .inputfield, "Forces a fresh detector run at least this often even while a tracked region is present, so a stale or wrong lock can recover — neither this node nor MediaPipe's own graph can otherwise notice tracking has drifted"))),
                ("outputRegionOfInterest", NodePort<simd_float4>(name: "Region", kind: .Outlet, description: "The tracked/detected region, or the full frame (0,0,1,1) if nothing was detected")),
                ("outputRotation", NodePort<Float>(name: "Rotation", kind: .Outlet, description: "Rotation for the tracked/detected region, or 0 if nothing was detected")),
                ("outputKeypoints", NodePort<ContiguousArray<simd_float2>>(name: "Keypoints", kind: .Outlet, description: "The detection's 4 raw BlazePose keypoints (mid-hip center, full-body size/rotation point, mid-shoulder center, upper-body size/rotation point, in that order), in Fabric's unit coordinate space (-1...1 horizontally, -aspect...aspect vertically) — empty if nothing was detected")),
            ]
        case .multi:
            return [
                ("inputMaxDetections", ParameterPort(parameter: IntParameter("Max Detections", 1, 1, 8, .inputfield, "Maximum number of bodies to detect"))),
                ("outputRegionsOfInterest", NodePort<ContiguousArray<simd_float4>>(name: "Regions", kind: .Outlet, description: "Detected body regions, confidence-sorted descending, as (x, y, width, height) normalized bottom-left-origin rects")),
                ("outputRotations", NodePort<ContiguousArray<Float>>(name: "Rotations", kind: .Outlet, description: "In-plane rotation in radians per region (index-aligned with Regions) — mid-hip-to-body-size-point angle, MediaPipe's own convention (image-raster Y-down, independent of the region's bottom-left-origin coordinate convention)")),
            ]
        }
    }

    private static func portOrder(for mode: MediaPipeDetectionMode) -> [String]
    {
        switch mode
        {
        case .single: return ["inputImage", "inputPreviousRegionOfInterest", "inputPreviousRotation", "inputRedetectInterval", "outputRegionOfInterest", "outputRotation", "outputKeypoints", "outputDetectionCount"]
        case .multi: return ["inputImage", "inputMaxDetections", "outputRegionsOfInterest", "outputRotations", "outputDetectionCount"]
        }
    }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to detect a body in")),
            ("outputDetectionCount", NodePort<Int>(name: "Count", kind: .Outlet, description: "Number of bodies actually detected")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var outputDetectionCount: NodePort<Int> { port(named: "outputDetectionCount") }

    public override func rebuildPorts(forStrategy strategy: String)
    {
        super.rebuildPorts(forStrategy: strategy)
        let mode = MediaPipeDetectionMode(rawValue: strategy) ?? .single
        let wanted = Self.dynamicPorts(for: mode)
        let wantedNames = Set(wanted.map(\.name))

        for name in Self.allDynamicPortNames.subtracting(wantedNames)
        {
            if let p = findPort(named: name) { removePort(p) }
        }
        for (name, p) in wanted where findPort(named: name) == nil
        {
            addDynamicPort(p, name: name)
        }

        let reordered: [Port] = Self.portOrder(for: mode).compactMap { findPort(named: $0) }
        if reordered.count == self.ports.count { reorderPorts(reordered) }

        self.framesSinceLastDetect = 0
        self.lastRects = []
    }

    private static let fullFrameRegion = simd_float4(0, 0, 1, 1)

    private static let defaultRedetectInterval = 30

    /// Consecutive frames served from a tracked region without running the
    /// detector. Reset to 0 whenever the detector actually runs, or the
    /// mode changes. Only ever touched from execute()/rebuildPorts on the
    /// graph thread.
    private var framesSinceLastDetect = 0

    private static var cachedModel: MediaPipeMPSGraph?
    private static let modelLock = NSLock()

    /// Not a port -- Fabric has no systemized protocol yet for per-node
    /// synchronous/asynchronous execution, so this stays a compile-time
    /// switch for development/comparison until that exists. Flip locally to
    /// test the bounded-GPU-wait path.
    private static let synchronousInference = false

    private var preprocessor: MediaPipeCropPreprocessor?

    /// GPU-resident destinations for MediaPipeMPSGraph.encode()'s output
    /// tensors (rawBoxes, rawScores) -- .storageModeShared so the completion
    /// handler can read them back without a CPU round-trip through submit().
    private var outputBuffers: [MTLBuffer]?

    private let lastRectsLock = NSLock()
    private var lastRectsStorage: [(region: simd_float4, rotation: Float, score: Float, keypoints: [simd_float2])] = []
    /// Backed by a lock because, under the async path, the GPU completion
    /// callback writes this from a thread other than execute()'s.
    private var lastRects: [(region: simd_float4, rotation: Float, score: Float, keypoints: [simd_float2])]
    {
        get
        {
            self.lastRectsLock.lock()
            defer { self.lastRectsLock.unlock() }
            return self.lastRectsStorage
        }
        set
        {
            self.lastRectsLock.lock()
            self.lastRectsStorage = newValue
            self.lastRectsLock.unlock()
        }
    }

    public override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        let mode = MediaPipeDetectionMode(rawValue: self.strategy) ?? .single

        if self.inputImage.valueDidChange, let inputImage = self.inputImage.value
        {
            switch mode
            {
            case .single:
                let redetectInterval = max(1, (findPort(named: "inputRedetectInterval") as ParameterPort<Int>?)?.value ?? Self.defaultRedetectInterval)
                let previousRegion: simd_float4? = (findPort(named: "inputPreviousRegionOfInterest") as NodePort<simd_float4>?)?.value

                if let previousRegion, self.framesSinceLastDetect < redetectInterval
                {
                    self.framesSinceLastDetect += 1
                    let previousRotation = (findPort(named: "inputPreviousRotation") as NodePort<Float>?)?.value ?? 0
                    self.lastRects = [(region: previousRegion, rotation: previousRotation, score: 1.0, keypoints: [])]
                }
                else
                {
                    self.framesSinceLastDetect = 0
                    try? self.detect(image: inputImage, maxDetections: 1, commandBuffer: commandBuffer, synchronous: Self.synchronousInference)
                }

            case .multi:
                let maxDetections = max(1, (findPort(named: "inputMaxDetections") as ParameterPort<Int>?)?.value ?? 1)
                try? self.detect(image: inputImage, maxDetections: maxDetections, commandBuffer: commandBuffer, synchronous: Self.synchronousInference)
            }
        }

        // One snapshot, reused below -- lastRects is lock-protected per
        // access, but the async completion handler can reassign it from a
        // background thread between two separate `self.lastRects` reads
        // (more likely now that N-deep pipelining lets several completions
        // land in quick succession). Reading it three times independently
        // risked regions/rotations/keypoints being derived from three
        // different detection sets, silently desyncing their indices.
        let currentRects = self.lastRects
        let regions = ContiguousArray(currentRects.map(\.region))
        let rotations = ContiguousArray(currentRects.map(\.rotation))

        switch mode
        {
        case .single:
            (findPort(named: "outputRegionOfInterest") as NodePort<simd_float4>?)?.send(regions.first ?? Self.fullFrameRegion)
            (findPort(named: "outputRotation") as NodePort<Float>?)?.send(rotations.first ?? 0)
            (findPort(named: "outputKeypoints") as NodePort<ContiguousArray<simd_float2>>?)?.send(self.unitKeypoints(currentRects.first?.keypoints ?? []))

        case .multi:
            (findPort(named: "outputRegionsOfInterest") as NodePort<ContiguousArray<simd_float4>>?)?.send(regions)
            (findPort(named: "outputRotations") as NodePort<ContiguousArray<Float>>?)?.send(rotations)
        }

        self.outputDetectionCount.send(regions.count)
    }

    /// Converts keypoints from this node's own bottom-left-origin normalized
    /// [0,1] space into Fabric's unit coordinate space (-1...1 horizontally,
    /// -aspect...aspect vertically). Empty when there's no current image to
    /// derive aspect from.
    private func unitKeypoints(_ keypoints: [simd_float2]) -> ContiguousArray<simd_float2>
    {
        guard keypoints.isEmpty == false, let image = self.inputImage.value else { return [] }
        let aspect = Float(image.presentationSize.height / image.presentationSize.width)
        return ContiguousArray(keypoints.map {
            simd_float2(remap($0.x, 0.0, 1.0, -1.0, 1.0), remap($0.y, 0.0, 1.0, -aspect, aspect))
        })
    }

    private func outputBuffers(for model: MediaPipeMPSGraph) throws -> [MTLBuffer]
    {
        if let existing = self.outputBuffers { return existing }

        let buffers = try model.outputBufferLengths.map { length -> MTLBuffer in
            guard let buffer = self.context.device.makeBuffer(length: length, options: .storageModeShared) else
            {
                throw FabricError(.execution(.outOfMemory), severity: .recoverable, message: "Could not allocate MediaPipe pose detection output buffer")
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
    /// this call when `synchronous` is true. Silently drops the cycle
    /// (never updates lastRects) if all maxFramesInFlight inference slots
    /// are already busy, matching MediaPipeMPSGraph.encode()'s and
    /// MediaPipeCropPreprocessor's own no-backlog semantics.
    private func detect(image: FabricImage, maxDetections: Int, commandBuffer: MTLCommandBuffer, synchronous: Bool) throws
    {
        let startTime = Date()
        let preprocessor = try self.preprocessor ?? MediaPipeCropPreprocessor(device: self.context.device, outputWidth: MediaPipePoseDetector.detectSize, outputHeight: MediaPipePoseDetector.detectSize, outputPixelRange: MediaPipePoseDetector.detectorPixelRange)
        self.preprocessor = preprocessor

        let model = try Self.mpsGraphModel(commandQueue: self.context.commandQueue)
        let outputBuffers = try self.outputBuffers(for: model)

        // Letterbox: full image, no rotation, square side = max(iw, ih), centered.
        let presentationSize = image.presentationSize
        let imageWidth = Float(presentationSize.width)
        let imageHeight = Float(presentationSize.height)
        let side = max(imageWidth, imageHeight)

        let targetBuffer: MTLCommandBuffer
        if synchronous
        {
            guard let dedicated = self.context.commandQueue.makeCommandBuffer() else
            {
                throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create synchronous MediaPipe pose detection command buffer")
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
            centerNormalizedBottomLeft: simd_float2(0.5, 0.5),
            sizeNormalized: simd_float2(side / imageWidth, side / imageHeight),
            rotationRadians: 0,
            commandBuffer: targetBuffer
        )

        guard try model.encode(inputBuffer: inputBuffer, outputBuffers: outputBuffers, commandBuffer: targetBuffer, commit: synchronous) else
        {
            return
        }

        // Captures no `self` -- safe to call from inside a [weak self]
        // completion handler without accidentally keeping this node alive
        // via the closure.
        func decodedRects() -> [(region: simd_float4, rotation: Float, score: Float, keypoints: [simd_float2])]?
        {
            let outputs = outputBuffers.map { buffer -> [Float] in
                let count = buffer.length / MemoryLayout<Float>.stride
                return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: Float.self), count: count))
            }
            guard outputs.count >= 2 else { return nil }
            return Self.decodeRects(rawBoxes: outputs[0], rawScores: outputs[1], maxDetections: maxDetections, imageWidth: imageWidth, imageHeight: imageHeight)
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
                print("MediaPipePoseDetectionNode: detection failed: \(error)")
                return
            }
            if let rects = decodedRects()
            {
                MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
                self.lastRects = rects
            }
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
                    print("MediaPipePoseDetectionNode: detection failed: \(error)")
                    return
                }
                if let rects = decodedRects()
                {
                    MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
                    self.lastRects = rects
                }
            }
        }
    }

    private static func decodeRects(rawBoxes: [Float], rawScores: [Float], maxDetections: Int, imageWidth: Float, imageHeight: Float) -> [(region: simd_float4, rotation: Float, score: Float, keypoints: [simd_float2])]
    {
        let detections = MediaPipePoseDetector.decodeDetections(rawBoxes: rawBoxes, rawScores: rawScores, maxDetections: maxDetections, imageWidth: imageWidth, imageHeight: imageHeight)

        return detections.map { detection in
            // Convert (cx, cy, w, h) top-left-origin normalized -> Fabric's
            // bottom-left-origin (x, y, w, h) rect convention. Rotation is
            // left unflipped.
            let regionBottomLeft = simd_float4(
                detection.region.cx - detection.region.width / 2,
                1 - (detection.region.cy - detection.region.height / 2) - detection.region.height,
                detection.region.width,
                detection.region.height
            )
            // keypoints are top-left-origin normalized full-image -- flip y
            // to match the region's bottom-left-origin convention.
            let keypointsBottomLeft = detection.keypoints.map { simd_float2($0.x, 1 - $0.y) }
            return (region: regionBottomLeft, rotation: detection.rotation, score: detection.score, keypoints: keypointsBottomLeft)
        }
    }

    private static func mpsGraphModel(commandQueue: MTLCommandQueue) throws -> MediaPipeMPSGraph
    {
        Self.modelLock.lock()
        defer { Self.modelLock.unlock() }

        if let existing = Self.cachedModel { return existing }

        let model = try MediaPipeMPSGraph.loadBundled(
            named: MediaPipePoseDetector.resourcePrefix,
            inputWidth: MediaPipePoseDetector.detectSize, inputHeight: MediaPipePoseDetector.detectSize,
            commandQueue: commandQueue
        )
        Self.cachedModel = model
        return model
    }
}
