//
//  MediaPipeFaceLandmarkNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import SwiftUI
import QuartzCore
import simd
import MPSMediaPipe

#if SWIFT_PACKAGE
import SatinCore
#endif

/// Which of MediaPipeFaceLandmarkNode's optional outputs (Geometry,
/// Transform) are present -- reshapes the node's port count, so it lives in
/// Settings rather than as a runtime value. Both default to off: most graphs
/// only want 2D/Scene-Space landmarks, and neither output is free to compute
/// (a Procrustes solve against the canonical face model).
public struct MediaPipeFaceLandmarkOutputSettings: Codable, Equatable
{
    public var enableGeometry: Bool
    public var enableTransform: Bool

    public init(enableGeometry: Bool = false, enableTransform: Bool = false)
    {
        self.enableGeometry = enableGeometry
        self.enableTransform = enableTransform
    }
}

/// Runs MediaPipe's FaceMesh landmark model (468 points, non-attention
/// variant — no iris refinement) against a caller-supplied region +
/// rotation. Standalone comparison path, mirroring
/// MediaPipeHandLandmarkNode's structure. Wire MediaPipe Face Detection's
/// Region/Rotation/Keypoints outputs into this node's matching inputs.
///
/// Unlike hand's 21 points (which map cleanly onto 5 named finger groups),
/// FaceMesh's 468-point topology has no equivalent small named grouping, so
/// this exposes the full landmark array rather than per-region ports.
///
/// Geometry and Transform are fit against the canonical face model
/// (FaceGeometrySolver, formerly the separate FaceGeometryNode/
/// FaceTransformNode — folded in here since both need the same raw
/// landmarks this node already holds). Each is a Settings toggle (Output
/// Settings), off by default: enabling one adds that port and starts
/// computing it every frame a face is present; disabling removes the port.
/// This is Settings-gated rather than connection-gated because the port's
/// very existence — not just whether its value gets computed — is what's
/// opt-in here, per the port-count-changes-only-via-Settings rule. Wire
/// Transform as Geometry's own placement transform; Transform matches
/// apparent size against whichever camera the graph is actually rendering
/// with (see Transform's own port description for the derivation), so it
/// stays correct under a custom camera, not just Fabric's default.
///
/// For multiple faces (MediaPipe Face Detection's Multi mode), this node's
/// own ports don't change — wire it inside an Iterator fed by Detection's
/// Regions/Rotations (Iterator Info + an Array Index Value node picking
/// Regions[i]/Rotations[i] per iteration; an Array Append/Queue node
/// collects each iteration's Landmarks back into an array). Running inside
/// an Iterator automatically forces synchronous inference and bypasses
/// smoothing for that execute() call — an Iterator re-executes this same
/// node instance N times sequentially within one frame, so the async
/// path's later-arriving completion and the one shared smoothing filter
/// would both apply to the wrong subject's data.
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
            ("inputRegionOfInterest", NodePort<simd_float4>(name: "Region", kind: .Inlet, description: "Face region as (x, y, width, height) normalized bottom-left-origin — wire in from MediaPipe Face Detection's Region output. Defaults to the full frame when unconnected.")),
            ("inputRotation", NodePort<Float>(name: "Rotation", kind: .Inlet, description: "In-plane rotation in radians — wire in from MediaPipe Face Detection's Rotation output. Defaults to 0 (no rotation) when unconnected.")),
            ("inputKeypoints", NodePort<ContiguousArray<simd_float2>>(name: "Keypoints", kind: .Inlet, description: "Detector keypoints, already in Fabric's unit coordinate space — wire in from MediaPipe Face Detection's Keypoints output. Passed straight through to this node's own Keypoints output so a single downstream consumer can see both the detector's coarse keypoints and the refined landmarks. Empty when unconnected.")),
            ("inputEnableSmoothing", ParameterPort(parameter: BoolParameter("Smoothing", true, .toggle, "Temporally smooth landmarks with a One Euro filter. Disable to see the model's raw, unsmoothed output."))),

            ("outputLandmarks", NodePort<ContiguousArray<simd_float2>>(name: "Landmarks", kind: .Outlet, description: "All 468 FaceMesh landmarks, in FaceMesh's own canonical index order, in unit coordinates")),
            ("outputLandmarksScene", NodePort<ContiguousArray<simd_float3>>(name: "Landmarks (Scene Space)", kind: .Outlet, description: "All 468 FaceMesh landmarks remapped into Fabric's unit coordinate space (-1...1 horizontally, -aspect...aspect vertically, matching Landmarks), z scaled by the same factor as x — directly comparable against MediaPipe Hand/Pose Landmarks' own Landmarks (Scene Space) output, so all three can be composited in one 3D scene. Not physically metric, and not camera-aligned — for an actual placement transform, use this node's own Transform output instead. Empty if nothing was detected.")),
            ("outputKeypoints", NodePort<ContiguousArray<simd_float2>>(name: "Keypoints", kind: .Outlet, description: "Pass-through of this node's Keypoints inlet, unchanged")),
            ("outputTrackedRegionOfInterest", NodePort<simd_float4>(name: "Tracked Region", kind: .Outlet, description: "This frame's landmarks re-expressed as a region for tracking the same face next frame, matching MediaPipe Face Detection's Previous Region inlet. Sent as nil (not a stale rect) whenever this frame's presence gate fails.")),
            ("outputTrackedRotation", NodePort<Float>(name: "Tracked Rotation", kind: .Outlet, description: "Paired with Tracked Region — wire into MediaPipe Face Detection's Previous Rotation inlet.")),
        ]
    }

    /// Geometry/Transform port descriptions, shared between the dynamic-port
    /// registration in rebuildOptionalPorts(for:) and anyone wanting the
    /// exact wording without re-deriving it.
    private static let geometryPortName = "outputGeometry"
    private static let transformPortName = "outputTransform"

    private static func makeGeometryPort() -> Port
    {
        NodePort<Geometry>(name: "Geometry", kind: .Outlet, description: "MediaPipe's canonical face model fit to this frame's landmarks (Procrustes solve): 468-vertex/898-triangle topology and UVs, vertex positions in centimeters with head pose normalized out — expression only, not rotation/translation. Wire Transform as this mesh's own placement. Not updated (retains its last value) when no face is present this frame.")
    }

    private static func makeTransformPort() -> Port
    {
        NodePort<simd_float4x4>(name: "Transform", kind: .Outlet, description: "Rigid placement transform (uniform scale + rotation + translation, head pose only) for the same solve as Geometry, fit directly against Landmarks (Scene Space)'s own already-camera-correct 3D reconstruction — inherits that output's real depth and placement, already in Fabric's world units. Not updated (retains its last value) when no face is present this frame.")
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputRegionOfInterest: NodePort<simd_float4> { port(named: "inputRegionOfInterest") }
    public var inputRotation: NodePort<Float> { port(named: "inputRotation") }
    public var inputKeypoints: NodePort<ContiguousArray<simd_float2>> { port(named: "inputKeypoints") }
    public var inputEnableSmoothing: ParameterPort<Bool> { port(named: "inputEnableSmoothing") }

    public var outputLandmarks: NodePort<ContiguousArray<simd_float2>> { port(named: "outputLandmarks") }
    public var outputLandmarksScene: NodePort<ContiguousArray<simd_float3>> { port(named: "outputLandmarksScene") }
    public var outputKeypoints: NodePort<ContiguousArray<simd_float2>> { port(named: "outputKeypoints") }
    public var outputTrackedRegionOfInterest: NodePort<simd_float4> { port(named: "outputTrackedRegionOfInterest") }
    public var outputTrackedRotation: NodePort<Float> { port(named: "outputTrackedRotation") }

    /// Present only when Output Settings enables them -- see outputSettings.
    public var outputGeometry: NodePort<Geometry>? { findPort(named: Self.geometryPortName) }
    public var outputTransform: NodePort<simd_float4x4>? { findPort(named: Self.transformPortName) }

    // MARK: - Output Settings (Geometry/Transform port presence)

    var outputSettings: MediaPipeFaceLandmarkOutputSettings
    {
        didSet
        {
            guard oldValue != outputSettings else { return }
            let previous = oldValue

            if let graph
            {
                graph.withoutUndoRegistration {
                    self.rebuildOptionalPorts(for: self.outputSettings)
                }
                graph.undoManager?.registerUndo(withTarget: self) { node in
                    node.outputSettings = previous
                }
                graph.undoManager?.setActionName("Change Face Landmark Output Settings")
            }
            else
            {
                self.rebuildOptionalPorts(for: self.outputSettings)
            }
        }
    }

    private enum OutputSettingsCodingKeys: String, CodingKey
    {
        case outputSettings
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: OutputSettingsCodingKeys.self)
        let decoded = try container.decodeIfPresent(MediaPipeFaceLandmarkOutputSettings.self, forKey: .outputSettings)

        // Initializing assignment -- didSet does not fire here, matching the
        // plain-creation path (ports are (re)built by rebuildOptionalPorts below).
        self.outputSettings = decoded ?? MediaPipeFaceLandmarkOutputSettings()

        try super.init(from: decoder)

        // Rebuild from the restored settings, evicting any dynamic port left
        // over from whatever settings the document was saved with.
        self.rebuildOptionalPorts(for: self.outputSettings)
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: OutputSettingsCodingKeys.self)
        try container.encode(self.outputSettings, forKey: .outputSettings)
    }

    public required init(context: Context)
    {
        self.outputSettings = MediaPipeFaceLandmarkOutputSettings()
        super.init(context: context)
        self.rebuildOptionalPorts(for: self.outputSettings)
    }

    /// Designated init for programmatic construction with specific initial output settings.
    public init(context: Context, outputSettings: MediaPipeFaceLandmarkOutputSettings)
    {
        self.outputSettings = outputSettings
        super.init(context: context)
        self.rebuildOptionalPorts(for: self.outputSettings)
    }

    private func rebuildOptionalPorts(for settings: MediaPipeFaceLandmarkOutputSettings)
    {
        if settings.enableGeometry
        {
            if findPort(named: Self.geometryPortName) == nil
            {
                addDynamicPort(Self.makeGeometryPort(), name: Self.geometryPortName)
            }
        }
        else if let existing = findPort(named: Self.geometryPortName)
        {
            removePort(existing)
        }

        if settings.enableTransform
        {
            if findPort(named: Self.transformPortName) == nil
            {
                addDynamicPort(Self.makeTransformPort(), name: Self.transformPortName)
            }
        }
        else if let existing = findPort(named: Self.transformPortName)
        {
            removePort(existing)
        }
    }

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool { true }
    override public var settingsSize: SettingsViewSize { .Mini }

    override public func settingsView() -> AnyView
    {
        AnyView(MediaPipeFaceLandmarkOutputSettingsView(model: self.outputSettingsModel))
    }

    private lazy var outputSettingsModel = OutputSettingsModel(node: self)

    @Observable final class OutputSettingsModel
    {
        var enableGeometry: Bool
        {
            didSet
            {
                guard let node, enableGeometry != node.outputSettings.enableGeometry else { return }
                node.outputSettings.enableGeometry = enableGeometry
            }
        }
        var enableTransform: Bool
        {
            didSet
            {
                guard let node, enableTransform != node.outputSettings.enableTransform else { return }
                node.outputSettings.enableTransform = enableTransform
            }
        }

        private weak var node: MediaPipeFaceLandmarkNode?

        init(node: MediaPipeFaceLandmarkNode)
        {
            self.node = node
            self.enableGeometry = node.outputSettings.enableGeometry
            self.enableTransform = node.outputSettings.enableTransform
        }
    }

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
    private let landmarksSmoothingFilter = MediaPipeLandmarksSmoothingFilter(debugLabel: "Face")
    private lazy var faceMeshGeometry = FaceMeshGeometry(context: self.context)

    private let lastLandmarksLock = NSLock()
    private var lastLandmarksStorage: [simd_float3] = []
    private var lastLandmarksTimestampStorage: CFTimeInterval = 0
    private var lastRegionStorage: simd_float4 = MediaPipeFaceLandmarkNode.fullFrameRegion
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

            do { try self.detectLandmarks(image: inputImage, region: region, rotation: rotation, commandBuffer: commandBuffer, synchronous: synchronous) }
            catch { print("MediaPipeFaceLandmarkNode: detectLandmarks failed: \(error)") }
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
        self.outputLandmarksScene.send(scenePoints)

        if self.outputGeometry != nil || self.outputTransform != nil
        {
            // Fits the canonical face model directly against scenePoints --
            // the same reconstruction already proven (both visually and via
            // direct A/B comparison against FaceGeometrySolver.solve()'s own
            // near-plane unprojection) to place correctly relative to
            // whichever camera is actually rendering the scene. poseTransform
            // then already maps canonical-model centimeters straight into
            // Fabric's world units, with no separate scale/placement
            // reconstruction needed -- see fitCanonicalModel's own doc for why
            // solve()'s own unprojectXY isn't used here.
            if let result = FaceGeometrySolver.fitCanonicalModel(to: Array(scenePoints))
            {
                if let outputGeometry = self.outputGeometry
                {
                    self.faceMeshGeometry.metricLandmarks = result.metricLandmarks
                    outputGeometry.send(self.faceMeshGeometry, force: true)
                }
                if let outputTransform = self.outputTransform
                {
                    outputTransform.send(result.poseTransform)
                }
            }
        }

        if let tracked = MediaPipeFaceLandmarkProjection.trackedRegion(from: self.lastLandmarks, presentationSize: inImage.presentationSize)
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
                throw FabricError(.execution(.outOfMemory), severity: .recoverable, message: "Could not allocate MediaPipe face landmark output buffer")
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
        let preprocessor = try self.preprocessor ?? MediaPipeCropPreprocessor(device: self.context.device, outputWidth: Int(MediaPipeFaceLandmarkProjection.landmarkSize), outputHeight: Int(MediaPipeFaceLandmarkProjection.landmarkSize))
        self.preprocessor = preprocessor

        let model = try Self.mpsGraphModel(commandQueue: self.context.commandQueue)
        let outputBuffers = try self.outputBuffers(for: model)

        let center = simd_float2(region.x + region.z / 2, region.y + region.w / 2)
        let size = simd_float2(region.z, region.w)

        let targetBuffer: MTLCommandBuffer
        if synchronous
        {
            guard let dedicated = self.context.commandQueue.makeCommandBuffer() else
            {
                throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create synchronous MediaPipe face landmark command buffer")
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
                print("MediaPipeFaceLandmarkNode: landmark detection failed: \(error)")
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
            targetBuffer.addCompletedHandler { [weak self, image] finishedBuffer in
                withExtendedLifetime(image) {}
                guard let self else { return }
                if let error = finishedBuffer.error
                {
                    print("MediaPipeFaceLandmarkNode: landmark detection failed: \(error)")
                    return
                }
                MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
                self.lastLandmarks = projectedLandmarks()
                self.lastRegion = region
            }
        }
    }

    /// outputs[0] = landmarks (1404 floats), outputs[1] = presence.
    private static func projectLandmarks(outputs: [[Float]], center: simd_float2, size: simd_float2, rotation: Float) -> [simd_float3]
    {
        guard outputs.count >= 2 else { return [] }
        let (landmarksRaw, presenceRaw) = (outputs[0], outputs[1])

        // `center` is bottom-left-origin; flip to top-left for the
        // projection math, then flip the result back below.
        guard let face = MediaPipeFaceLandmarkProjection.project(
            landmarksRaw: landmarksRaw,
            presenceRaw: presenceRaw.first ?? -Float.greatestFiniteMagnitude,
            rect: (cx: center.x, cy: 1 - center.y, width: size.x, height: size.y, rotation: rotation)
        ) else
        {
            // Most likely cause when Region/Rotation are left
            // unconnected: the model is fed the whole frame stretched into a
            // square, an out-of-distribution input for FaceMesh. Wire in
            // MediaPipe Face Detection's Region/Rotation outputs.
            return []
        }

        return face.landmarks.map { simd_float3($0.x, 1 - $0.y, $0.z) }
    }

    private static func mpsGraphModel(commandQueue: MTLCommandQueue) throws -> MediaPipeMPSGraph
    {
        try MediaPipeSharedModels.model(named: MediaPipeFaceLandmarkProjection.resourcePrefix, inputWidth: Int(MediaPipeFaceLandmarkProjection.landmarkSize), inputHeight: Int(MediaPipeFaceLandmarkProjection.landmarkSize), commandQueue: commandQueue)
    }

    /// `landmark` is normalized full-image, bottom-left origin.
    private func unitPoint(from landmark: simd_float3, aspect: Float) -> simd_float2
    {
        simd_float2(remap(landmark.x, 0.0, 1.0, -1.0, 1.0),
                    remap(landmark.y, 0.0, 1.0, -aspect, aspect))
    }

    /// x/y start from the same flat remap as unitPoint(), then get scaled by
    /// `depthScale` before z is added — without that, a point pulled off the
    /// z=0 plane no longer lines up with its own 2D position once viewed
    /// through a real perspective camera (the default one, at
    /// `PerspectiveCameraNode.defaultPosition.z`): a point closer to the
    /// camera needs *less* world x/y to land at the same screen position a
    /// flat point would, one farther away needs more — by exactly
    /// `(cameraDistance - z) / cameraDistance`, similar triangles along the
    /// camera's own viewing axis. Skipping that scaling is what made this
    /// output overshoot outward from center at the face's edges compared to
    /// Landmarks' own (correct) alignment.
    ///
    /// z itself is negated relative to MediaPipe's own landmark.z: raw z
    /// gets *more negative* the closer a point is to the camera (confirmed
    /// via `FaceGeometrySolver.canonicalPositions`, which is already in
    /// Fabric's own convention — nose tip z=+7.48 vs ear z=-2.0 — and via
    /// `FaceGeometrySolver.changeHandedness`, which negates raw z to reach
    /// that same array), the opposite of Fabric's own camera, which sits at
    /// positive z looking toward the origin, so *larger* z is closer. Scale
    /// factor 2 matches x's own [0,1]->[-1,1] remap, keeping z's magnitude
    /// on the same scale as x — what makes Face/Hand/Pose Landmarks' scene-
    /// space output directly comparable, independent of each model's own
    /// per-model depth-normalization constant (see
    /// MediaPipeFaceLandmarkProjection.normalizeZ).
    private func scenePoint(from landmark: simd_float3, aspect: Float) -> simd_float3
    {
        let flat = unitPoint(from: landmark, aspect: aspect)
        let depth = -landmark.z * 2
        let cameraDistance = PerspectiveCameraNode.defaultPosition.z
        let depthScale = (cameraDistance - depth) / cameraDistance
        return simd_float3(flat.x * depthScale, flat.y * depthScale, depth)
    }

}

/// Satin geometry sharing FaceGeometrySolver's canonical topology/UVs, with
/// per-frame-updated vertex positions and recomputed smooth normals.
/// Vertex/index buffers must be allocated with plain `malloc` (not Swift's
/// `UnsafeMutablePointer.allocate`) since SatinGeometry frees them with `free`.
private final class FaceMeshGeometry: SatinGeometry
{
    var metricLandmarks: [simd_float3] = FaceGeometrySolver.canonicalPositions
    {
        didSet { self._updateData = true }
    }

    override func generateGeometryData() -> GeometryData
    {
        let positions = self.metricLandmarks
        let uvs = FaceGeometrySolver.canonicalUVs
        let triangles = FaceGeometrySolver.canonicalTriangles
        let vertexCount = positions.count
        let indexCount = triangles.count

        guard
            vertexCount == uvs.count, vertexCount > 0, indexCount > 0,
            let vertexRaw = malloc(vertexCount * MemoryLayout<SatinVertex>.stride),
            let indexRaw = malloc(indexCount * MemoryLayout<TriangleIndices>.stride)
        else
        {
            return createGeometryData()
        }

        let vertexPointer = vertexRaw.bindMemory(to: SatinVertex.self, capacity: vertexCount)
        let indexPointer = indexRaw.bindMemory(to: TriangleIndices.self, capacity: indexCount)

        let normals = Self.computeSmoothNormals(positions: positions, triangles: triangles)
        for index in 0..<vertexCount
        {
            vertexPointer[index] = SatinVertex(position: positions[index], normal: normals[index], uv: uvs[index])
        }
        for (index, triangle) in triangles.enumerated()
        {
            indexPointer[index] = TriangleIndices(i0: triangle.0, i1: triangle.1, i2: triangle.2)
        }

        return GeometryData(vertexCount: Int32(vertexCount), vertexData: vertexPointer, indexCount: Int32(indexCount), indexData: indexPointer)
    }

    private static func computeSmoothNormals(positions: [simd_float3], triangles: [(UInt32, UInt32, UInt32)]) -> [simd_float3]
    {
        var normals = [simd_float3](repeating: .zero, count: positions.count)
        for triangle in triangles
        {
            let i0 = Int(triangle.0), i1 = Int(triangle.1), i2 = Int(triangle.2)
            let faceNormal = simd_cross(positions[i1] - positions[i0], positions[i2] - positions[i0])
            normals[i0] += faceNormal
            normals[i1] += faceNormal
            normals[i2] += faceNormal
        }
        return normals.map { simd_length($0) > 1e-12 ? simd_normalize($0) : simd_float3(0, 0, 1) }
    }
}

private struct MediaPipeFaceLandmarkOutputSettingsView: View
{
    @Bindable var model: MediaPipeFaceLandmarkNode.OutputSettingsModel

    var body: some View
    {
        VStack(alignment: .leading)
        {
            Toggle("Geometry Output", isOn: $model.enableGeometry)
            Toggle("Transform Output", isOn: $model.enableTransform)
        }
        .padding()
    }
}
