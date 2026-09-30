//
//  MediaPipeHandDetectionNode.swift
//  Fabric
//

import Foundation
import Metal
import MetalPerformanceShaders
import Satin
import simd
import MPSMediaPipe
import SwiftUI

/// Detects hands using MediaPipe's BlazePalm detector. Standalone
/// comparison test against the RTMDet-based RegionDetectionNode — not
/// wired into that pipeline. Outputs a region (matching
/// RegionDetectionNode's own bottom-left-origin simd_float4 convention)
/// plus a separate rotation in radians — MediaPipeHandLandmarkNode
/// consumes both directly.
///
/// Single/Multi is a Settings choice (see MediaPipeDetectionMode) since it
/// reshapes this node's ports, not a runtime value:
///
/// Single mode tracks exactly one hand and exposes the tracking fast path
/// — wire MediaPipe Hand Landmark's outputTrackedRegionOfInterest/
/// outputTrackedRotation back into this node's Tracked Region/Previous
/// Rotation inputs to skip re-running the detector while tracking holds. A
/// nil Tracked Region or the port left unconnected both fall through to
/// running the detector, so this is a no-op when unwired. Redetect
/// Interval forces a fresh detector run periodically even while a previous
/// region is present.
///
/// Multi mode detects up to Max Detections hands every frame (no tracking
/// fast path — see MediaPipeDetectionMode's own header for why) and
/// exposes plural Regions/Rotations. Wire those into an Iterator (with
/// Iterator Info + an Array Index Value node picking Regions[i]/
/// Rotations[i] per iteration) feeding a single MediaPipe Hand Landmark
/// node inside — not a change to the Landmark node itself.
public class MediaPipeHandDetectionNode: StrategyNode
{
    override public class var name: String { "MediaPipe Hand Detection" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Detects hands using MediaPipe's BlazePalm detector, run via MPSGraph (test/comparison path, separate from RegionDetectionNode/RTMDet). Single/Multi mode (Settings) picks between one tracked hand with Tracked Region/Rotation, or up to Max Detections hands with plural Regions/Rotations." }

    override public class var strategyOptions: [any NodeStrategyOption] { MediaPipeDetectionMode.allCases }

    /// The Single/Multi mode is a Settings choice, not part of the node's name:
    /// the title stays the plain type name (or the user's rename).
    override public func deriveSubtitle() -> String? { nil }

    override public var settingsSize: SettingsViewSize { .Small }

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
                ("inputPreviousRegionOfInterest", NodePort<simd_float4>(name: "Tracked Region", kind: .Inlet, description: "Optional tracking fast path — wire in MediaPipe Hand Landmark's Tracked Region output. When present (and the redetect interval hasn't elapsed), the detector model is skipped and this region is passed straight through. Leave unconnected for plain per-frame detection.")),
                ("inputPreviousRotation", NodePort<Float>(name: "Tracked Rotation", kind: .Inlet, description: "Paired with Tracked Region — wire in MediaPipe Hand Landmark's Tracked Rotation output.")),
                ("inputRedetectInterval", ParameterPort(parameter: IntParameter("Re-Detect Interval", Self.defaultRedetectInterval, 1, 240, .inputfield, "Forces a fresh detector run at least this often even while a tracked region is present, so a stale or wrong lock can recover"))),
                ("outputRegionOfInterest", NodePort<simd_float4>(name: "Region", kind: .Outlet, description: "The tracked/detected region, or the full frame (0,0,1,1) if nothing was detected")),
                ("outputRotation", NodePort<Float>(name: "Rotation", kind: .Outlet, description: "Rotation for the tracked/detected region, or 0 if nothing was detected")),
                ("outputKeypoints", NodePort<ContiguousArray<simd_float2>>(name: "Keypoints", kind: .Outlet, description: "The detection's 7 raw BlazePalm keypoints (wrist, index MCP, middle MCP, ring MCP, pinky MCP, thumb CMC, thumb MCP, in that order — confirmed against Mediapipe-Hands-PyTorch-CoreML's whim_data.py), in Fabric's unit coordinate space (-1...1 horizontally, -aspect...aspect vertically) — empty if nothing was detected")),
            ]
        case .multi:
            return [
                ("inputMaxDetections", ParameterPort(parameter: IntParameter("Max Detections", 2, 1, 16, .inputfield, "Maximum number of hands to detect"))),
                ("outputRegionsOfInterest", NodePort<ContiguousArray<simd_float4>>(name: "Regions", kind: .Outlet, description: "Detected hand regions, confidence-sorted descending, as (x, y, width, height) normalized bottom-left-origin rects")),
                ("outputRotations", NodePort<ContiguousArray<Float>>(name: "Rotations", kind: .Outlet, description: "In-plane rotation in radians per region (index-aligned with Regions) — wrist-to-middle-finger angle, MediaPipe's own convention (image-raster Y-down, independent of the region's bottom-left-origin coordinate convention)")),
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
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to detect hands in")),
            ("outputDetectionCount", NodePort<Int>(name: "Count", kind: .Outlet, description: "Number of hands actually detected")),
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

    /// Consecutive frames served from a tracked region (Tracked Region inlet)
    /// without running the detector. Reset to 0 whenever the detector
    /// actually runs, or the mode changes. Only ever touched from
    /// execute()/rebuildPorts on the graph thread.
    private var framesSinceLastDetect = 0



    private var preprocessor: MediaPipeCropPreprocessor?

    /// GPU-resident destinations for MediaPipeMPSGraph.encode()'s output
    /// tensors (rawBoxes, rawScores) -- .storageModeShared so the completion
    /// handler can read them back without a CPU round-trip through submit().
    private var outputBuffers: [MTLBuffer]?
    private var model: MediaPipeMPSGraph?
    private var preparedExecution: MPSModelExecution?

    public private(set) var modelPrecision: MPSModelPrecision = .highQuality
    public private(set) var modelComputeUnits: MPSModelComputeUnits = .gpuAndNeuralEngine
    public private(set) var inferenceTiming: MPSInferenceTiming = .synchronous

    private enum ModelPrecisionCodingKeys: String, CodingKey
    {
        case modelPrecision
        case modelComputeUnits
        case inferenceTiming
    }

    public required init(context: Context)
    {
        super.init(context: context)
    }

    public init(context: Context, mode: MediaPipeDetectionMode = .single, modelPrecision: MPSModelPrecision = .highQuality, modelComputeUnits: MPSModelComputeUnits = .gpuAndNeuralEngine, inferenceTiming: MPSInferenceTiming = .synchronous)
    {
        self.modelPrecision = modelPrecision
        self.modelComputeUnits = modelComputeUnits
        self.inferenceTiming = inferenceTiming
        super.init(context: context, initialStrategy: mode.rawValue)
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: ModelPrecisionCodingKeys.self)
        self.modelPrecision = try container.decodeIfPresent(MPSModelPrecision.self, forKey: .modelPrecision) ?? .highQuality
        self.modelComputeUnits = try container.decodeIfPresent(MPSModelComputeUnits.self, forKey: .modelComputeUnits) ?? .gpuAndNeuralEngine
        self.inferenceTiming = try container.decodeIfPresent(MPSInferenceTiming.self, forKey: .inferenceTiming) ?? .synchronous
        try super.init(from: decoder)
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: ModelPrecisionCodingKeys.self)
        try container.encode(self.modelPrecision, forKey: .modelPrecision)
        try container.encode(self.modelComputeUnits, forKey: .modelComputeUnits)
        try container.encode(self.inferenceTiming, forKey: .inferenceTiming)
    }

    override public func settingsView() -> AnyView
    {
        AnyView(MediaPipeDetectionSettingsView(
            strategyModel: self.strategySettingsModel,
            precision: Binding(
                get: { [weak self] in (self?.modelPrecision ?? .highQuality).label },
                set: { [weak self] value in
                    guard let self, let precision = MPSModelPrecision(label: value) else { return }
                    self.apply(modelPrecision: precision)
                }
            ),
            computeUnits: Binding(
                get: { [weak self] in (self?.modelComputeUnits ?? .gpuAndNeuralEngine).label },
                set: { [weak self] value in
                    guard let self, let computeUnits = MPSModelComputeUnits(label: value) else { return }
                    self.apply(modelComputeUnits: computeUnits)
                }
            ),
            inferenceTiming: Binding(
                get: { [weak self] in (self?.inferenceTiming ?? .synchronous).label },
                set: { [weak self] value in
                    guard let self, let inferenceTiming = MPSInferenceTiming(label: value) else { return }
                    self.apply(inferenceTiming: inferenceTiming)
                }
            )
        ))
    }

    override public func enableExecution(renderer: GraphRenderer) throws
    {
        try self.prepareModel(execution: self.modelExecution)
        try super.enableExecution(renderer: renderer)
    }

    override public func disableExecution(renderer: GraphRenderer) throws
    {
        self.model = nil
        self.preprocessor = nil
        self.outputBuffers = nil
        self.preparedExecution = nil
        try super.disableExecution(renderer: renderer)
    }

    private func apply(modelPrecision: MPSModelPrecision)
    {
        guard modelPrecision != self.modelPrecision else { return }
        // A loaded model means execution is enabled: swap it now, keeping the
        // old one if the new precision fails to load.
        if self.model != nil
        {
            do
            {
                try self.prepareModel(execution: MPSModelExecution(precision: modelPrecision, computeUnits: self.modelComputeUnits))
            }
            catch
            {
                print("MediaPipeHandDetectionNode: could not apply precision: \(error)")
                return
            }
        }
        self.modelPrecision = modelPrecision
        self.markDirty()
    }

    private func apply(modelComputeUnits: MPSModelComputeUnits)
    {
        guard modelComputeUnits != self.modelComputeUnits else { return }
        // A loaded model means execution is enabled: swap it now, keeping the
        // old one if the new compute units fail to load.
        if self.model != nil
        {
            do
            {
                try self.prepareModel(execution: MPSModelExecution(precision: self.modelPrecision, computeUnits: modelComputeUnits))
            }
            catch
            {
                print("MediaPipeHandDetectionNode: could not apply compute units: \(error)")
                return
            }
        }
        self.modelComputeUnits = modelComputeUnits
        self.markDirty()
    }

    private var modelExecution: MPSModelExecution
    {
        MPSModelExecution(precision: self.modelPrecision, computeUnits: self.modelComputeUnits)
    }

    /// Takes effect on the next frame; the model does not change.
    private func apply(inferenceTiming: MPSInferenceTiming)
    {
        guard inferenceTiming != self.inferenceTiming else { return }
        self.inferenceTiming = inferenceTiming
        self.markDirty()
    }

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
                    try? self.detect(image: inputImage, maxDetections: 1, commandBuffer: commandBuffer, synchronous: self.inferenceTiming == .synchronous)
                }

            case .multi:
                let maxDetections = max(1, (findPort(named: "inputMaxDetections") as ParameterPort<Int>?)?.value ?? 2)
                try? self.detect(image: inputImage, maxDetections: maxDetections, commandBuffer: commandBuffer, synchronous: self.inferenceTiming == .synchronous)
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
                throw FabricError(.execution(.outOfMemory), severity: .recoverable, message: "Could not allocate MediaPipe hand detection output buffer")
            }
            return buffer
        }
        self.outputBuffers = buffers
        return buffers
    }

    /// Async: encodes crop-and-normalize AND MPSGraph inference onto Fabric's
    /// shared `commandBuffer`, never committed by this node (its owner, the
    /// render loop, commits it once at the end of the frame). Synchronous:
    /// encodes the crop onto a dedicated buffer this call commits without
    /// waiting, then calls the model's `run()`, which waits once on its own
    /// buffer on the same queue. Silently drops the cycle
    /// (never updates lastRects) if all maxFramesInFlight inference slots
    /// are already busy, matching MediaPipeMPSGraph.encode()'s and
    /// MediaPipeCropPreprocessor's own no-backlog semantics.
    private func detect(image: FabricImage, maxDetections: Int, commandBuffer: MTLCommandBuffer, synchronous: Bool) throws
    {
        let startTime = Date()
        try self.prepareModel(execution: self.modelExecution)
        guard let preprocessor = self.preprocessor, let model = self.model else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "MediaPipe hand detection model is unavailable")
        }
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
                throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create synchronous MediaPipe hand detection command buffer")
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

        // Captures no `self` -- safe to call from inside a [weak self]
        // completion handler without accidentally keeping this node alive
        // via the closure.
        func decodedRects(_ outputs: [[Float]]) -> [(region: simd_float4, rotation: Float, score: Float, keypoints: [simd_float2])]?
        {
            guard outputs.count >= 2 else { return nil }
            return Self.decodeRects(rawBoxes: outputs[0], rawScores: outputs[1], maxDetections: maxDetections, imageWidth: imageWidth, imageHeight: imageHeight)
        }

        if synchronous
        {
            // The crop's dedicated buffer is committed without a wait;
            // run() encodes onto its own buffer on the same queue, so the
            // GPU runs inference after the crop, and run() waits once.
            targetBuffer.commit()
            let outputs = try model.run(inputBuffer: inputBuffer)
            if let rects = decodedRects(outputs)
            {
                MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
                self.lastRects = rects
            }
            return
        }

        guard let frameCommandBuffer = targetBuffer as? MPSCommandBuffer else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "MediaPipe hand detection requires Fabric's per-frame MPSCommandBuffer")
        }
        guard try model.encode(inputBuffer: inputBuffer, outputBuffers: outputBuffers, commandBuffer: frameCommandBuffer) else
        {
            return
        }

        // Keeps `image` (and its texture) out of GraphRendererTextureCache's
        // recycle pool until the GPU work reading it is verified done, not
        // just encoded.
        frameCommandBuffer.addCompletedHandler { [weak self, image, model, preprocessor, inputBuffer] finishedBuffer in
            withExtendedLifetime((image, model, preprocessor, inputBuffer)) {}
            guard let self else { return }
            if let error = finishedBuffer.error
            {
                print("MediaPipeHandDetectionNode: detection failed: \(error)")
                return
            }
            let outputs = outputBuffers.map { buffer -> [Float] in
                let count = buffer.length / MemoryLayout<Float>.stride
                return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: Float.self), count: count))
            }
            if let rects = decodedRects(outputs)
            {
                MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
                self.lastRects = rects
            }
        }
    }

    private static func decodeRects(rawBoxes: [Float], rawScores: [Float], maxDetections: Int, imageWidth: Float, imageHeight: Float) -> [(region: simd_float4, rotation: Float, score: Float, keypoints: [simd_float2])]
    {
        let detections = MediaPipeHandDetector.decodeDetections(rawBoxes: rawBoxes, rawScores: rawScores, maxDetections: maxDetections, imageWidth: imageWidth, imageHeight: imageHeight)

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

    private static func mpsGraphModel(execution: MPSModelExecution, commandQueue: MTLCommandQueue) throws -> MediaPipeMPSGraph
    {
        try MediaPipeSharedModels.model(named: MediaPipeHandDetector.resourcePrefix, inputWidth: MediaPipeHandDetector.detectSize, inputHeight: MediaPipeHandDetector.detectSize, execution: execution, commandQueue: commandQueue)
    }

    private func prepareModel(execution: MPSModelExecution) throws
    {
        guard self.model == nil || self.preparedExecution != execution else { return }
        let model = try Self.mpsGraphModel(execution: execution, commandQueue: self.context.commandQueue)
        self.preprocessor = try MediaPipeCropPreprocessor(
            device: self.context.device,
            outputWidth: MediaPipeHandDetector.detectSize,
            outputHeight: MediaPipeHandDetector.detectSize
        )
        self.outputBuffers = nil
        _ = try self.outputBuffers(for: model)
        self.model = model
        self.preparedExecution = execution
    }
}
