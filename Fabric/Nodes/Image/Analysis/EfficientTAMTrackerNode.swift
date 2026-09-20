//
//  EfficientTAMTrackerNode.swift
//  Fabric
//

import Foundation
import Metal
import MetalPerformanceShaders
import Satin
import simd
import MPSEfficientTAM

/// Tracks one object through video with EfficientTAM (Tiny, 512), via MPSGraph.
///
/// Give it a point on the object and fire Prompt: that frame becomes the
/// conditioning frame, and every following frame is segmented using the
/// tracker's memory of earlier frames. It is forward-only and follows a single
/// object. It does not assume anything about color space: the texels of the
/// input image go to the model as they are, so convert upstream if needed.
///
/// Every stage (frame pack, image encode, memory attention, decode, mask
/// selection, memory encode, mask projection) is encoded back to back onto
/// Fabric's shared per-frame `MPSCommandBuffer` and is never committed by this
/// node, so the Mask image is available downstream in the same frame with no
/// GPU wait. Only the small scalar results (region, centroid, presence,
/// confidence) are read back, in the buffer's completion handler, so they
/// arrive one or more frames later, stamped by the Frame Time output. With
/// `synchronousInference` they are read back immediately instead, as in the
/// MediaPipe nodes: see `encodeFrame`.
public final class EfficientTAMTrackerNode: Node
{
    override public class var name: String { "MPS EfficientTAM Tracker" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String
    {
        "Tracks one object through video with EfficientTAM via Metal Performance Shaders Graph. Set Prompt Point on the object and fire Prompt to start tracking from the current frame. Forward-only, one object. Outputs a 128x128 mask (upsample downstream, e.g. with a Joint Bilateral Filter guided by the source image), the object's region and centroid, and whether it is currently visible."
    }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) +
        [
            ("inputImage", NodePort<FabricImage>(
                name: "Image",
                kind: .Inlet,
                description: "Video frame to track through. Only new images advance the tracker. Colors are passed to the model unchanged, so convert to the color space you want upstream."
            )),
            ("inputPromptPoint", ParameterPort(parameter: Float2Parameter(
                "Prompt Point",
                .zero,
                .inputfield,
                "A point on the object to track, in Fabric's unit space (-1...1 horizontally, -aspect...aspect vertically)"
            ))),
            ("inputPrompt", ParameterPort(parameter: BoolParameter(
                "Prompt",
                false,
                .button,
                "Start tracking from the current frame at Prompt Point. Firing again while tracking restarts from that frame."
            ))),
            ("inputReset", ParameterPort(parameter: BoolParameter(
                "Reset",
                false,
                .button,
                "Stop tracking and drop all memory of earlier frames"
            ))),
            ("inputFrameTime", NodePort<Float>(
                name: "Frame Time",
                kind: .Inlet,
                description: "Optional source time of the image in seconds, for example a Movie Provider's Current Time. Used to detect jumps in time. Uses graph time when unconnected."
            )),
            ("inputMaxFrameGap", ParameterPort(parameter: FloatParameter(
                "Max Frame Gap",
                0.0,
                0.0,
                60.0,
                .inputfield,
                "Seconds. If the time between consecutive frames exceeds this, tracking stops until Prompt fires again. 0 disables the check. Time moving backwards always stops tracking, as the tracker only runs forward."
            ))),

            ("outputMask", NodePort<FabricImage>(
                name: "Mask",
                kind: .Outlet,
                description: "Probability that each pixel belongs to the tracked object, single-channel Float32 at the model's native 128x128 resolution, not presentation resolution. Zero everywhere while the object is absent. Upsample downstream, e.g. with a Joint Bilateral Filter guided by the source image."
            )),
            ("outputRegion", NodePort<simd_float4>(
                name: "Region",
                kind: .Outlet,
                description: "Bounding box of the mask as (x, y, width, height) normalized, bottom-left origin, matching MediaPipe's regions. Nil while the object is absent. Arrives with the readback, so it can trail the Mask by a frame or more; see Frame Time."
            )),
            ("outputCentroid", NodePort<simd_float2>(
                name: "Centroid",
                kind: .Outlet,
                description: "Center of mass of the mask in Fabric's unit space. Nil while the object is absent. Trails the Mask like Region."
            )),
            ("outputPresent", NodePort<Bool>(
                name: "Present",
                kind: .Outlet,
                description: "True while the tracker believes the object is visible. The tracker can lose the object behind an occluder and find it again."
            )),
            ("outputConfidence", NodePort<Float>(
                name: "Confidence",
                kind: .Outlet,
                description: "0...1 confidence that the object is present in the frame"
            )),
            ("outputTracking", NodePort<Bool>(
                name: "Tracking",
                kind: .Outlet,
                description: "True while a tracking session is active, from Prompt until Reset, a time jump, or another Prompt"
            )),
            ("outputFrameTime", NodePort<Float>(
                name: "Frame Time",
                kind: .Outlet,
                description: "Source time of the frame that Region, Centroid, Present and Confidence describe"
            )),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputPromptPoint: ParameterPort<simd_float2> { port(named: "inputPromptPoint") }
    public var inputPrompt: NodePort<Bool> { port(named: "inputPrompt") }
    public var inputReset: NodePort<Bool> { port(named: "inputReset") }
    public var inputFrameTime: NodePort<Float> { port(named: "inputFrameTime") }
    public var inputMaxFrameGap: ParameterPort<Float> { port(named: "inputMaxFrameGap") }

    public var outputMask: NodePort<FabricImage> { port(named: "outputMask") }
    public var outputRegion: NodePort<simd_float4> { port(named: "outputRegion") }
    public var outputCentroid: NodePort<simd_float2> { port(named: "outputCentroid") }
    public var outputPresent: NodePort<Bool> { port(named: "outputPresent") }
    public var outputConfidence: NodePort<Float> { port(named: "outputConfidence") }
    public var outputTracking: NodePort<Bool> { port(named: "outputTracking") }
    public var outputFrameTime: NodePort<Float> { port(named: "outputFrameTime") }

    /// Not a port -- Fabric has no systemized protocol yet for per-node
    /// synchronous/asynchronous execution, so this stays a compile-time switch
    /// like the MediaPipe nodes' (an Iterator forces synchronous regardless).
    /// Flip locally for offline rendering, where every frame must be tracked
    /// and every result must be available in the frame that produced it.
    private static let synchronousInference = false

    /// Frames of tracking work allowed on the GPU at once. Every MPSGraph stage
    /// that MPSGraph splits across command buffers takes a queue slot, and Metal
    /// stalls the CPU when a queue's command buffer cap (64 by default) is
    /// reached, so two keeps `execute()` from ever blocking on a default queue.
    private static let framesInFlight = 2

    private static let maskSize = EfficientTAMMaskProjector.maskSize
    private static let modelSide = Float(EfficientTAMImageEncoder.inputWidth)

    private enum TrackingState: Equatable
    {
        case idle
        case tracking
        case objectAbsent
    }

    private struct TrackedFrameResult
    {
        let sequenceIdentifier: Int
        let frameTime: Float
        let isPresent: Bool
        let confidence: Float
        let region: simd_float4
        let centroid: simd_float2
    }

    private var tracker: EfficientTAMVideoTracker?
    private var framePreprocessor: EfficientTAMFramePreprocessor?
    private var maskProjector: EfficientTAMMaskProjector?

    /// Bumped whenever a session starts or ends, so results still in flight
    /// from an earlier session are ignored when they arrive.
    private var sequenceIdentifier = 0
    private var isSessionActive = false
    private var pendingPromptPoint: simd_float2?
    private var lastSubmittedFrameTime: Float?

    /// Written by the GPU completion handler, read by `execute()`.
    private let latestResultLock = NSLock()
    private var latestResult: TrackedFrameResult?
    private var hasUnpublishedResult = false

    private var trackingState: TrackingState = .idle
    {
        didSet
        {
            if self.trackingState != oldValue { self.subtitleSubject.send() }
        }
    }

    override public func deriveSubtitle() -> String?
    {
        switch self.trackingState
        {
        case .idle: nil
        case .tracking: "Tracking"
        case .objectAbsent: "Object absent"
        }
    }

    override public func stopExecution(renderer: GraphRenderer) throws
    {
        self.endSession(clearingOutputs: false)
        self.tracker = nil
        self.framePreprocessor = nil
        self.maskProjector = nil
    }

    override public func execute(
        renderer: GraphRenderer,
        executionInfo: GraphExecutionInfo,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) throws
    {
        if self.inputReset.valueDidChange, self.inputReset.value == true
        {
            self.endSession(clearingOutputs: true)
        }

        let promptFired = self.inputPrompt.valueDidChange && self.inputPrompt.value == true
        if promptFired
        {
            // A new prompt always starts a new sequence from the current frame.
            self.endSession(clearingOutputs: false)
            self.pendingPromptPoint = self.inputPromptPoint.value ?? .zero
        }

        if let inputImage = self.inputImage.value
        {
            let frameTime = self.inputFrameTime.value ?? Float(executionInfo.timing.time)
            let synchronous = Self.synchronousInference || executionInfo.iterationInfo != nil

            if let promptPoint = self.pendingPromptPoint
            {
                // Retried on later frames until the tracker has a free slot.
                if try self.encodeFrame(
                    image: inputImage,
                    frameTime: frameTime,
                    promptPoint: promptPoint,
                    renderer: renderer,
                    commandBuffer: commandBuffer,
                    synchronous: synchronous
                )
                {
                    self.pendingPromptPoint = nil
                    self.isSessionActive = true
                    self.lastSubmittedFrameTime = frameTime
                    self.trackingState = .tracking
                    self.outputTracking.send(true)
                }
            }
            else if self.isSessionActive, self.inputImage.valueDidChange
            {
                if self.isTimeDiscontinuity(frameTime: frameTime)
                {
                    self.endSession(clearingOutputs: true)
                }
                else if try self.encodeFrame(
                    image: inputImage,
                    frameTime: frameTime,
                    promptPoint: nil,
                    renderer: renderer,
                    commandBuffer: commandBuffer,
                    synchronous: synchronous
                )
                {
                    self.lastSubmittedFrameTime = frameTime
                }
            }
        }

        self.publishLatestResult()
    }

    // MARK: - Session

    private func endSession(clearingOutputs: Bool)
    {
        self.tracker?.reset()
        self.sequenceIdentifier += 1
        self.isSessionActive = false
        self.pendingPromptPoint = nil
        self.lastSubmittedFrameTime = nil
        self.latestResultLock.lock()
        self.latestResult = nil
        self.hasUnpublishedResult = false
        self.latestResultLock.unlock()

        guard clearingOutputs else { return }
        self.trackingState = .idle
        self.outputMask.send(nil)
        self.outputRegion.send(nil)
        self.outputCentroid.send(nil)
        self.outputPresent.send(false)
        self.outputConfidence.send(0)
        self.outputTracking.send(false)
        self.outputFrameTime.send(nil)
    }

    /// The tracker only runs forward through evenly-consecutive frames, so a
    /// backward jump, or a gap larger than the user allows, ends the session.
    private func isTimeDiscontinuity(frameTime: Float) -> Bool
    {
        guard let lastFrameTime = self.lastSubmittedFrameTime else { return false }
        let gap = frameTime - lastFrameTime
        if gap < 0 { return true }
        let maximumGap = self.inputMaxFrameGap.value ?? 0
        return maximumGap > 0 && gap > maximumGap
    }

    // MARK: - Encoding

    /// Encodes the frame pack, the whole tracker chain and the mask projection,
    /// one after the other, onto either Fabric's shared `commandBuffer` (async)
    /// or a dedicated one this call owns exclusively (synchronous) -- the same
    /// encode calls either way. Never committed by this node when sharing
    /// Fabric's buffer (the render loop commits it once at the end of the
    /// frame); committed and waited on immediately when synchronous.
    ///
    /// Synchronous caveat, shared with the MediaPipe nodes: the dedicated buffer
    /// runs before Fabric's shared one, so an input image whose texels are
    /// produced by GPU work encoded earlier this same frame is read stale.
    ///
    /// Returns false, having changed nothing visible, when the tracker has no
    /// free slot: the frame is dropped and the next one tried.
    private func encodeFrame(
        image: FabricImage,
        frameTime: Float,
        promptPoint: simd_float2?,
        renderer: GraphRenderer,
        commandBuffer: MTLCommandBuffer,
        synchronous: Bool
    ) throws -> Bool
    {
        try self.prepareModel()
        guard let tracker, let framePreprocessor, let maskProjector else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "EfficientTAM tracker is unavailable")
        }

        let synchronousCommandBuffer: MPSCommandBuffer?
        let targetBuffer: MTLCommandBuffer
        if synchronous
        {
            guard let dedicated = self.context.commandQueue.makeCommandBuffer() else
            {
                throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create the synchronous EfficientTAM command buffer")
            }
            let wrapped = MPSCommandBuffer(commandBuffer: dedicated)
            synchronousCommandBuffer = wrapped
            targetBuffer = wrapped
        }
        else
        {
            synchronousCommandBuffer = nil
            targetBuffer = commandBuffer
        }

        guard let modelInput = self.context.device.makeBuffer(
            length: framePreprocessor.outputBufferLength,
            options: .storageModePrivate
        ) else
        {
            throw FabricError(.execution(.outOfMemory), severity: .recoverable, message: "Could not allocate the EfficientTAM frame buffer")
        }
        modelInput.label = "EfficientTAM Frame"

        try framePreprocessor.encode(
            inputTexture: image.texture,
            textureTransform: image.textureTransform,
            outputBuffer: modelInput,
            commandBuffer: targetBuffer
        )

        let trackingOutput: EfficientTAMVideoTrackingOutput?
        if let promptPoint
        {
            let modelPoint = Self.modelPoint(fromUnitPoint: promptPoint, image: image)
            trackingOutput = try tracker.encodeInitialFrame(
                inputBuffer: modelInput,
                prompts: [
                    EfficientTAMPrompt(x: modelPoint.x, y: modelPoint.y, label: .positivePoint),
                    EfficientTAMPrompt(x: 0, y: 0, label: .padding),
                ],
                commandBuffer: targetBuffer,
                commit: false
            )
        }
        else
        {
            trackingOutput = try tracker.encodeNextFrame(inputBuffer: modelInput, commandBuffer: targetBuffer, commit: false)
        }
        guard let trackingOutput else { return false }

        let maskImage = try renderer.newImage(withWidth: Self.maskSize, height: Self.maskSize, format: .r32Float)
        maskImage.texture.label = "EfficientTAM Mask (\(Self.maskSize)x\(Self.maskSize))"
        try maskProjector.encode(
            maskLogitsBuffer: trackingOutput.maskLogitsBuffer,
            outputTexture: maskImage.texture,
            applySigmoid: true,
            commandBuffer: targetBuffer
        )

        // The scalars are tiny: mask logits, then the object score logit.
        let maskByteCount = Self.maskSize * Self.maskSize * MemoryLayout<Float>.stride
        guard let readbackBuffer = self.context.device.makeBuffer(
            length: maskByteCount + MemoryLayout<Float>.stride,
            options: .storageModeShared
        ), let blitEncoder = targetBuffer.makeBlitCommandEncoder() else
        {
            throw FabricError(.execution(.outOfMemory), severity: .recoverable, message: "Could not create the EfficientTAM readback")
        }
        readbackBuffer.label = "EfficientTAM Readback"
        blitEncoder.label = "EfficientTAM Readback Blit"
        blitEncoder.copy(from: trackingOutput.maskLogitsBuffer, sourceOffset: 0, to: readbackBuffer, destinationOffset: 0, size: maskByteCount)
        blitEncoder.copy(from: trackingOutput.objectScoreLogitBuffer, sourceOffset: 0, to: readbackBuffer, destinationOffset: maskByteCount, size: MemoryLayout<Float>.stride)
        blitEncoder.endEncoding()

        let sequenceIdentifier = self.sequenceIdentifier
        let aspect = Float(image.presentationSize.height / image.presentationSize.width)

        // Captures no `self`.
        func decodeResult() -> TrackedFrameResult
        {
            Self.decodeResult(
                readbackBuffer: readbackBuffer,
                sequenceIdentifier: sequenceIdentifier,
                frameTime: frameTime,
                aspect: aspect
            )
        }

        if let synchronousCommandBuffer
        {
            // This node owns the wrapper, so it commits it, once.
            synchronousCommandBuffer.commit()
            synchronousCommandBuffer.waitUntilCompleted()
            if let error = synchronousCommandBuffer.error
            {
                print("EfficientTAMTrackerNode: tracking failed: \(error)")
                return true
            }
            self.store(decodeResult())
        }
        else
        {
            // Keeps everything the GPU is still reading or writing out of the
            // texture cache's recycle pool until the work is verified done, not
            // just encoded.
            targetBuffer.addCompletedHandler { [weak self, image, maskImage, trackingOutput, modelInput] finishedBuffer in
                withExtendedLifetime((image, maskImage, trackingOutput, modelInput)) {}
                guard let self else { return }
                if let error = finishedBuffer.error
                {
                    print("EfficientTAMTrackerNode: tracking failed: \(error)")
                    return
                }
                self.store(decodeResult())
            }
        }

        self.outputMask.send(maskImage)
        return true
    }

    private func prepareModel() throws
    {
        guard self.tracker == nil else { return }
        let tracker = try EfficientTAMVideoTracker(
            commandQueue: self.context.commandQueue,
            maxFramesInFlight: Self.framesInFlight
        )
        // One compile, done here rather than in the first tracked frame.
        try tracker.prewarmMemoryAttention()
        self.framePreprocessor = try EfficientTAMFramePreprocessor(device: self.context.device)
        self.maskProjector = try EfficientTAMMaskProjector(device: self.context.device)
        self.tracker = tracker
    }

    // MARK: - Results

    private func store(_ result: TrackedFrameResult)
    {
        self.latestResultLock.lock()
        self.latestResult = result
        self.hasUnpublishedResult = true
        self.latestResultLock.unlock()
    }

    private func publishLatestResult()
    {
        self.latestResultLock.lock()
        let result = self.hasUnpublishedResult ? self.latestResult : nil
        self.hasUnpublishedResult = false
        self.latestResultLock.unlock()

        // Results from an earlier session can still arrive after a reset.
        guard let result, result.sequenceIdentifier == self.sequenceIdentifier else { return }

        self.trackingState = result.isPresent ? .tracking : .objectAbsent
        self.outputPresent.send(result.isPresent)
        self.outputConfidence.send(result.confidence)
        self.outputRegion.send(result.isPresent ? result.region : nil)
        self.outputCentroid.send(result.isPresent ? result.centroid : nil)
        self.outputFrameTime.send(result.frameTime)
        self.outputTracking.send(self.isSessionActive)
    }

    /// Fabric's unit space (x in -1...1, y in -aspect...aspect, up) to model
    /// pixels (0...512, origin top-left, y down).
    private static func modelPoint(fromUnitPoint point: simd_float2, image: FabricImage) -> simd_float2
    {
        let aspect = Float(image.presentationSize.height / image.presentationSize.width)
        let normalizedX = (point.x + 1) * 0.5
        let normalizedYFromBottom = (point.y / aspect + 1) * 0.5
        return simd_float2(
            min(max(normalizedX, 0), 1) * Self.modelSide,
            (1 - min(max(normalizedYFromBottom, 0), 1)) * Self.modelSide
        )
    }

    /// Reads the mask logits and object score the blit copied out, and derives
    /// the region, centroid and presence from the pixels the model calls object
    /// (logit above zero).
    private static func decodeResult(
        readbackBuffer: MTLBuffer,
        sequenceIdentifier: Int,
        frameTime: Float,
        aspect: Float
    ) -> TrackedFrameResult
    {
        let size = Self.maskSize
        let values = readbackBuffer.contents().assumingMemoryBound(to: Float.self)
        let objectScoreLogit = values[size * size]

        var minimumColumn = size
        var minimumRow = size
        var maximumColumn = -1
        var maximumRow = -1
        var columnSum = 0.0
        var rowSum = 0.0
        var pixelCount = 0
        for row in 0..<size
        {
            for column in 0..<size where values[row * size + column] > 0
            {
                minimumColumn = min(minimumColumn, column)
                maximumColumn = max(maximumColumn, column)
                minimumRow = min(minimumRow, row)
                maximumRow = max(maximumRow, row)
                columnSum += Double(column)
                rowSum += Double(row)
                pixelCount += 1
            }
        }

        let isPresent = objectScoreLogit > 0 && pixelCount > 0
        let sizeFloat = Float(size)
        var region = simd_float4.zero
        var centroid = simd_float2.zero
        if pixelCount > 0
        {
            // Rows count down from the top; regions are bottom-left origin.
            region = simd_float4(
                Float(minimumColumn) / sizeFloat,
                1 - Float(maximumRow + 1) / sizeFloat,
                Float(maximumColumn - minimumColumn + 1) / sizeFloat,
                Float(maximumRow - minimumRow + 1) / sizeFloat
            )
            let centroidX = (Float(columnSum / Double(pixelCount)) + 0.5) / sizeFloat
            let centroidYFromBottom = 1 - (Float(rowSum / Double(pixelCount)) + 0.5) / sizeFloat
            centroid = simd_float2(centroidX * 2 - 1, (centroidYFromBottom * 2 - 1) * aspect)
        }

        return TrackedFrameResult(
            sequenceIdentifier: sequenceIdentifier,
            frameTime: frameTime,
            isPresent: isPresent,
            confidence: 1 / (1 + exp(-objectScoreLogit)),
            region: region,
            centroid: centroid
        )
    }
}
