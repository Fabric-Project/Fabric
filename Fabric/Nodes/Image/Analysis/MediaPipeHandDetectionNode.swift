//
//  MediaPipeHandDetectionNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Detects hands using MediaPipe's BlazePalm detector, run via a from-
/// scratch MPSGraph port of the model's own resolved TFLite op graph (see
/// MediaPipeTFLiteMPSGraph.swift) — no CoreML. Standalone comparison test
/// against the RTMDet-based RegionDetectionNode — not wired into that
/// pipeline. Outputs a region (matching RegionDetectionNode's own bottom-
/// left-origin simd_float4 convention) plus a separate rotation in radians,
/// rather than a composite rotated-rect type — MediaPipeHandLandmarkNode
/// consumes both directly.
public class MediaPipeHandDetectionNode: Node
{
    override public class var name: String { "MediaPipe Hand Detection" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Detects hands using MediaPipe's BlazePalm detector, run via MPSGraph (test/comparison path, separate from RegionDetectionNode/RTMDet). Outputs a region and a separate rotation in radians — wire both into MediaPipe Hand Landmark's matching inputs." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to detect hands in")),
            ("inputMaxDetections", ParameterPort(parameter: IntParameter("Max Detections", 2, 1, 16, .inputfield, "Maximum number of hands to detect"))),

            ("outputRegionsOfInterest", NodePort<ContiguousArray<simd_float4>>(name: "Regions", kind: .Outlet, description: "Detected hand regions, confidence-sorted descending, as (x, y, width, height) normalized bottom-left-origin rects")),
            ("outputRegionOfInterest", NodePort<simd_float4>(name: "Region", kind: .Outlet, description: "The single best detected region, or the full frame (0,0,1,1) if nothing was detected")),
            ("outputRotations", NodePort<ContiguousArray<Float>>(name: "Rotations", kind: .Outlet, description: "In-plane rotation in radians per region (index-aligned with Regions) — wrist-to-middle-finger angle, MediaPipe's own convention (image-raster Y-down, independent of the region's bottom-left-origin coordinate convention)")),
            ("outputRotation", NodePort<Float>(name: "Rotation", kind: .Outlet, description: "Rotation for the single best region, or 0 if nothing was detected")),
            ("outputDetectionCount", NodePort<Int>(name: "Count", kind: .Outlet, description: "Number of hands actually detected")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputMaxDetections: ParameterPort<Int> { port(named: "inputMaxDetections") }

    public var outputRegionsOfInterest: NodePort<ContiguousArray<simd_float4>> { port(named: "outputRegionsOfInterest") }
    public var outputRegionOfInterest: NodePort<simd_float4> { port(named: "outputRegionOfInterest") }
    public var outputRotations: NodePort<ContiguousArray<Float>> { port(named: "outputRotations") }
    public var outputRotation: NodePort<Float> { port(named: "outputRotation") }
    public var outputDetectionCount: NodePort<Int> { port(named: "outputDetectionCount") }

    private static let fullFrameRegion = simd_float4(0, 0, 1, 1)
    private static let anchors = MediaPipeHandAnchors.generate()

    private static var cachedModel: MediaPipeTFLiteMPSGraph?
    private static let modelLock = NSLock()

    /// Not a Setting yet — a plain toggle while the async path is
    /// validated, mirroring HandPoseAnalysisNode's own toggle. false:
    /// synchronous run(), blocks execute() until the GPU finishes. true:
    /// submit(), which encodes crop+inference onto one command buffer
    /// without waiting and updates lastRects from a completion callback
    /// ~1 frame (or more, under load) later.
    private static let useAsynchronousInference = true

    private var preprocessor: MediaPipeHandCropPreprocessor?

    private let lastRectsLock = NSLock()
    private var lastRectsStorage: [(region: simd_float4, rotation: Float, score: Float)] = []
    /// Backed by a lock because, under the async path, the GPU completion
    /// callback writes this from a thread other than execute()'s.
    private var lastRects: [(region: simd_float4, rotation: Float, score: Float)]
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
        if self.inputImage.valueDidChange, let inputImage = self.inputImage.value
        {
            let maxDetections = max(1, self.inputMaxDetections.value ?? 2)

            if Self.useAsynchronousInference
            {
                try? self.submitDetect(image: inputImage, maxDetections: maxDetections)
            }
            else if let rects = try? self.detect(image: inputImage, maxDetections: maxDetections)
            {
                self.lastRects = rects
            }
        }

        let regions = ContiguousArray(self.lastRects.map(\.region))
        let rotations = ContiguousArray(self.lastRects.map(\.rotation))

        self.outputRegionsOfInterest.send(regions)
        self.outputRegionOfInterest.send(regions.first ?? Self.fullFrameRegion)
        self.outputRotations.send(rotations)
        self.outputRotation.send(rotations.first ?? 0)
        self.outputDetectionCount.send(regions.count)
    }

    private func detect(image: FabricImage, maxDetections: Int) throws -> [(region: simd_float4, rotation: Float, score: Float)]
    {
        let preprocessor = try self.preprocessor ?? MediaPipeHandCropPreprocessor(device: self.context.device, outputWidth: MediaPipeHandAnchors.detectSize, outputHeight: MediaPipeHandAnchors.detectSize)
        self.preprocessor = preprocessor

        let model = try Self.mpsGraphModel(commandQueue: self.context.commandQueue)

        // Letterbox: full image, no rotation, square side = max(iw, ih),
        // centered — matches fasthands.pipeline._detect_rects exactly.
        let presentationSize = image.presentationSize
        let imageWidth = Float(presentationSize.width)
        let imageHeight = Float(presentationSize.height)
        let side = max(imageWidth, imageHeight)

        let inputBuffer = try preprocessor.encode(
            image: image,
            centerNormalizedBottomLeft: simd_float2(0.5, 0.5),
            sizeNormalized: simd_float2(side / imageWidth, side / imageHeight),
            rotationRadians: 0,
            commandQueue: self.context.commandQueue
        )

        let outputs = model.run(inputBuffer: inputBuffer)
        guard outputs.count >= 2 else { return [] }
        return Self.decodeRects(rawBoxes: outputs[0], rawScores: outputs[1], maxDetections: maxDetections, imageWidth: imageWidth, imageHeight: imageHeight)
    }

    /// Async counterpart of detect(): encodes crop+inference onto one
    /// command buffer without waiting, updating lastRects from the
    /// completion callback once the GPU finishes. Silently drops the frame
    /// (never updates lastRects) if an inference is already in flight,
    /// matching detect()'s no-backlog semantics.
    private func submitDetect(image: FabricImage, maxDetections: Int) throws
    {
        let preprocessor = try self.preprocessor ?? MediaPipeHandCropPreprocessor(device: self.context.device, outputWidth: MediaPipeHandAnchors.detectSize, outputHeight: MediaPipeHandAnchors.detectSize)
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
            image: image,
            centerNormalizedBottomLeft: simd_float2(0.5, 0.5),
            sizeNormalized: simd_float2(side / imageWidth, side / imageHeight),
            rotationRadians: 0,
            commandBuffer: commandBuffer
        )

        model.submit(inputBuffer: inputBuffer, commandBuffer: commandBuffer) { [weak self] result in
            guard let self, case .success(let outputs) = result, outputs.count >= 2 else { return }
            self.lastRects = Self.decodeRects(rawBoxes: outputs[0], rawScores: outputs[1], maxDetections: maxDetections, imageWidth: imageWidth, imageHeight: imageHeight)
        }
    }

    private static func decodeRects(rawBoxes: [Float], rawScores: [Float], maxDetections: Int, imageWidth: Float, imageHeight: Float) -> [(region: simd_float4, rotation: Float, score: Float)]
    {
        let decoded = MediaPipeHandDetectorDecoder.decode(rawBoxes: rawBoxes, rawScores: rawScores, anchors: Self.anchors)
        let merged = MediaPipeHandDetectorDecoder.weightedNonMaximumSuppression(decoded)
        let topDetections = merged.sorted { $0.score > $1.score }.prefix(maxDetections)

        return topDetections.map { detection in
            let projected = MediaPipeHandRectTransform.project(detection, imageWidth: imageWidth, imageHeight: imageHeight)
            let rect = MediaPipeHandRectTransform.handRect(from: projected, imageWidth: imageWidth, imageHeight: imageHeight)

            // Convert (cx, cy, w, h) top-left-origin normalized -> Fabric's
            // bottom-left-origin (x, y, w, h) rect convention. Rotation is
            // left unflipped -- see this node's outputRotation description.
            let regionBottomLeft = simd_float4(
                rect.cx - rect.width / 2,
                1 - (rect.cy - rect.height / 2) - rect.height,
                rect.width,
                rect.height
            )
            return (region: regionBottomLeft, rotation: rect.rotation, score: detection.score)
        }
    }

    private static func mpsGraphModel(commandQueue: MTLCommandQueue) throws -> MediaPipeTFLiteMPSGraph
    {
        Self.modelLock.lock()
        defer { Self.modelLock.unlock() }

        if let existing = Self.cachedModel { return existing }

        guard
            let binaryURL = Bundle.module.url(forResource: "MediaPipeHandDetector_weights", withExtension: "bin", subdirectory: "Models/Pose"),
            let manifestURL = Bundle.module.url(forResource: "MediaPipeHandDetector_weights", withExtension: "json", subdirectory: "Models/Pose"),
            let opsURL = Bundle.module.url(forResource: "MediaPipeHandDetector_ops", withExtension: "json", subdirectory: "Models/Pose")
        else
        {
            throw FabricError(.execution(.failed), severity: .recoverable, message: "Could not find bundled MediaPipeHandDetector graph resources")
        }

        let model = try MediaPipeTFLiteMPSGraph(
            weightsBinaryURL: binaryURL, weightsManifestURL: manifestURL, opsJSONURL: opsURL,
            inputWidth: MediaPipeHandAnchors.detectSize, inputHeight: MediaPipeHandAnchors.detectSize,
            commandQueue: commandQueue
        )
        Self.cachedModel = model
        return model
    }
}
