//
//  MediaPipeHandDetectionNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd
import MPSMediaPipe

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
/// outputTrackedRotation back into this node's Previous Region/Previous
/// Rotation inputs to skip re-running the detector while tracking holds. A
/// nil Previous Region or the port left unconnected both fall through to
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
    override public class var nodeDescription: String { "Detects hands using MediaPipe's BlazePalm detector, run via MPSGraph (test/comparison path, separate from RegionDetectionNode/RTMDet). Single/Multi mode (Settings) picks between one tracked hand with Previous Region/Rotation, or up to Max Detections hands with plural Regions/Rotations." }

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
                ("inputPreviousRegionOfInterest", NodePort<simd_float4>(name: "Previous Region", kind: .Inlet, description: "Optional tracking fast path — wire in MediaPipe Hand Landmark's Tracked Region output. When present (and the redetect interval hasn't elapsed), the detector model is skipped and this region is passed straight through. Leave unconnected for plain per-frame detection.")),
                ("inputPreviousRotation", NodePort<Float>(name: "Previous Rotation", kind: .Inlet, description: "Paired with Previous Region — wire in MediaPipe Hand Landmark's Tracked Rotation output.")),
                ("inputRedetectInterval", ParameterPort(parameter: IntParameter("Re-detect Every N Frames", Self.defaultRedetectInterval, 1, 240, .inputfield, "Forces a fresh detector run at least this often even while a tracked region is present, so a stale or wrong lock can recover"))),
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

    /// Consecutive frames served from a tracked region (Previous Region inlet)
    /// without running the detector. Reset to 0 whenever the detector
    /// actually runs, or the mode changes. Only ever touched from
    /// execute()/rebuildPorts on the graph thread.
    private var framesSinceLastDetect = 0

    private static var cachedModel: MediaPipeMPSGraph?
    private static let modelLock = NSLock()

    /// Not a Setting yet -- plain toggle while the async path is validated.
    /// false: synchronous run(), blocks execute() until the GPU finishes.
    /// true: submit(), updates lastRects from a completion callback ~1
    /// frame (or more, under load) later.
    private static let useAsynchronousInference = false

    private var preprocessor: MediaPipeCropPreprocessor?

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

                    if Self.useAsynchronousInference
                    {
                        try? self.submitDetect(image: inputImage, maxDetections: 1)
                    }
                    else if let rects = try? self.detect(image: inputImage, maxDetections: 1)
                    {
                        self.lastRects = rects
                    }
                }

            case .multi:
                let maxDetections = max(1, (findPort(named: "inputMaxDetections") as ParameterPort<Int>?)?.value ?? 2)

                if Self.useAsynchronousInference
                {
                    try? self.submitDetect(image: inputImage, maxDetections: maxDetections)
                }
                else if let rects = try? self.detect(image: inputImage, maxDetections: maxDetections)
                {
                    self.lastRects = rects
                }
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

    private func detect(image: FabricImage, maxDetections: Int) throws -> [(region: simd_float4, rotation: Float, score: Float, keypoints: [simd_float2])]
    {
        let startTime = Date()
        let preprocessor = try self.preprocessor ?? MediaPipeCropPreprocessor(device: self.context.device, outputWidth: MediaPipeHandDetector.detectSize, outputHeight: MediaPipeHandDetector.detectSize)
        self.preprocessor = preprocessor

        let model = try Self.mpsGraphModel(commandQueue: self.context.commandQueue)

        // Letterbox: full image, no rotation, square side = max(iw, ih), centered.
        let presentationSize = image.presentationSize
        let imageWidth = Float(presentationSize.width)
        let imageHeight = Float(presentationSize.height)
        let side = max(imageWidth, imageHeight)

        let inputBuffer = try preprocessor.encode(
            texture: image.texture,
            textureTransform: image.textureTransform,
            centerNormalizedBottomLeft: simd_float2(0.5, 0.5),
            sizeNormalized: simd_float2(side / imageWidth, side / imageHeight),
            rotationRadians: 0,
            commandQueue: self.context.commandQueue
        )

        let outputs = model.run(inputBuffer: inputBuffer)
        MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
        guard outputs.count >= 2 else { return [] }
        return Self.decodeRects(rawBoxes: outputs[0], rawScores: outputs[1], maxDetections: maxDetections, imageWidth: imageWidth, imageHeight: imageHeight)
    }

    /// Async counterpart of detect(): encodes crop+inference onto one
    /// command buffer without waiting, updating lastRects from the
    /// completion callback once the GPU finishes. Silently drops the frame
    /// (never updates lastRects) if all in-flight slots are busy,
    /// matching detect()'s no-backlog semantics -- now N-deep instead of
    /// single-flight (see MediaPipeCropPreprocessor's maxFramesInFlight).
    private func submitDetect(image: FabricImage, maxDetections: Int) throws
    {
        let startTime = Date()
        let preprocessor = try self.preprocessor ?? MediaPipeCropPreprocessor(device: self.context.device, outputWidth: MediaPipeHandDetector.detectSize, outputHeight: MediaPipeHandDetector.detectSize)
        self.preprocessor = preprocessor

        let model = try Self.mpsGraphModel(commandQueue: self.context.commandQueue)

        let presentationSize = image.presentationSize
        let imageWidth = Float(presentationSize.width)
        let imageHeight = Float(presentationSize.height)
        let side = max(imageWidth, imageHeight)

        guard let commandBuffer = self.context.commandQueue.makeCommandBuffer() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create asynchronous MediaPipe hand detection command buffer")
        }

        let inputBuffer = try preprocessor.encode(
            texture: image.texture,
            textureTransform: image.textureTransform,
            centerNormalizedBottomLeft: simd_float2(0.5, 0.5),
            sizeNormalized: simd_float2(side / imageWidth, side / imageHeight),
            rotationRadians: 0,
            commandBuffer: commandBuffer
        )

        model.submit(inputBuffer: inputBuffer, commandBuffer: commandBuffer) { [weak self, image] result in
            guard let self, case .success(let outputs) = result, outputs.count >= 2 else { return }
            MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
            self.lastRects = Self.decodeRects(rawBoxes: outputs[0], rawScores: outputs[1], maxDetections: maxDetections, imageWidth: imageWidth, imageHeight: imageHeight)
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

    private static func mpsGraphModel(commandQueue: MTLCommandQueue) throws -> MediaPipeMPSGraph
    {
        Self.modelLock.lock()
        defer { Self.modelLock.unlock() }

        if let existing = Self.cachedModel { return existing }

        let model = try MediaPipeMPSGraph.loadBundled(
            named: MediaPipeHandDetector.resourcePrefix,
            inputWidth: MediaPipeHandDetector.detectSize, inputHeight: MediaPipeHandDetector.detectSize,
            commandQueue: commandQueue
        )
        Self.cachedModel = model
        return model
    }
}
