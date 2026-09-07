//
//  MediaPipeFaceDetectionNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Detects faces using MediaPipe's BlazeFace (short-range) detector, run via
/// the shared generic MPSGraph TFLite interpreter (see
/// MediaPipeTFLiteMPSGraph.swift) — no CoreML. Standalone comparison path,
/// mirroring MediaPipeHandDetectionNode's structure exactly (same shared
/// anchor/decode/rect-transform types, same sync/async toggle). Outputs a
/// region (matching RegionDetectionNode's own bottom-left-origin simd_float4
/// convention) plus a separate rotation in radians — MediaPipeFaceLandmarkNode
/// consumes both directly.
///
/// Config values (128x128 input, 6 keypoints, [-1,1] pixel normalize,
/// rotation from left/right eye targeting 0°, rect scale 1.5 with no shift)
/// confirmed directly against mediapipe/modules/face_detection/
/// face_detection_short_range.pbtxt and face_detection_front_detection_to_roi.pbtxt
/// — there is no local third-party reference for BlazeFace the way
/// fasthands.pipeline validated BlazePalm, so the CNN/anchor/decode math is
/// numerically validated against the real converted model (see
/// MediaPipeTFLiteMPSGraph.swift's header), but the ROI/rotation geometry is
/// validated by formula derivation and hand-checked sanity cases only, not
/// against a real detected face end-to-end.
public class MediaPipeFaceDetectionNode: Node
{
    override public class var name: String { "MediaPipe Face Detection" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Detects faces using MediaPipe's BlazeFace short-range detector, run via MPSGraph (test/comparison path, separate from RegionDetectionNode/RTMDet — RTMDet has no face-detector checkpoint at all). Outputs a region and a separate rotation in radians — wire both into MediaPipe Face Landmark's matching inputs." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to detect faces in")),
            ("inputMaxDetections", ParameterPort(parameter: IntParameter("Max Detections", 2, 1, 16, .inputfield, "Maximum number of faces to detect"))),

            ("outputRegionsOfInterest", NodePort<ContiguousArray<simd_float4>>(name: "Regions", kind: .Outlet, description: "Detected face regions, confidence-sorted descending, as (x, y, width, height) normalized bottom-left-origin rects")),
            ("outputRegionOfInterest", NodePort<simd_float4>(name: "Region", kind: .Outlet, description: "The single best detected region, or the full frame (0,0,1,1) if nothing was detected")),
            ("outputRotations", NodePort<ContiguousArray<Float>>(name: "Rotations", kind: .Outlet, description: "In-plane rotation in radians per region (index-aligned with Regions) — left-eye-to-right-eye angle, MediaPipe's own convention (image-raster Y-down, independent of the region's bottom-left-origin coordinate convention)")),
            ("outputRotation", NodePort<Float>(name: "Rotation", kind: .Outlet, description: "Rotation for the single best region, or 0 if nothing was detected")),
            ("outputDetectionCount", NodePort<Int>(name: "Count", kind: .Outlet, description: "Number of faces actually detected")),
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

    // BlazeFace-short-range-specific constants (see MediaPipeHandDetectionNode
    // for BlazePalm's own values — same shared types, different constants).
    private static let detectSize = 128
    private static let numKeypoints = 6
    private static let detectorPixelRange: (min: Float, max: Float) = (-1, 1)
    private static let rotationKeypoints = (start: 0, end: 1) // left eye -> right eye
    private static let targetAngleRadians: Float = 0.0
    private static let rectScale: Float = 1.5

    private static let anchors = MediaPipeSSDAnchors.generate(detectSize: detectSize)

    private static var cachedModel: MediaPipeTFLiteMPSGraph?
    private static let modelLock = NSLock()

    /// Not a Setting yet — a plain toggle while the async path is
    /// validated, mirroring MediaPipeHandDetectionNode's own toggle.
    private static let useAsynchronousInference = true

    private var preprocessor: MediaPipeCropPreprocessor?

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
        let preprocessor = try self.preprocessor ?? MediaPipeCropPreprocessor(device: self.context.device, outputWidth: Self.detectSize, outputHeight: Self.detectSize, outputPixelRange: Self.detectorPixelRange)
        self.preprocessor = preprocessor

        let model = try Self.mpsGraphModel(commandQueue: self.context.commandQueue)

        // Letterbox: full image, no rotation, square side = max(iw, ih),
        // centered — matches MediaPipeHandDetectionNode's own letterbox
        // (same ImageToTensorCalculator keep_aspect_ratio convention).
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
        let preprocessor = try self.preprocessor ?? MediaPipeCropPreprocessor(device: self.context.device, outputWidth: Self.detectSize, outputHeight: Self.detectSize, outputPixelRange: Self.detectorPixelRange)
        self.preprocessor = preprocessor

        let model = try Self.mpsGraphModel(commandQueue: self.context.commandQueue)

        let presentationSize = image.presentationSize
        let imageWidth = Float(presentationSize.width)
        let imageHeight = Float(presentationSize.height)
        let side = max(imageWidth, imageHeight)

        guard let commandBuffer = self.context.commandQueue.makeCommandBuffer() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create asynchronous MediaPipe face detection command buffer")
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
        let decoded = MediaPipeSSDDetectorDecoder.decode(rawBoxes: rawBoxes, rawScores: rawScores, anchors: Self.anchors, numKeypoints: Self.numKeypoints, detectSize: Self.detectSize)
        let merged = MediaPipeSSDDetectorDecoder.weightedNonMaximumSuppression(decoded)
        let topDetections = merged.sorted { $0.score > $1.score }.prefix(maxDetections)

        return topDetections.map { detection in
            let projected = MediaPipeSSDRectTransform.project(detection, imageWidth: imageWidth, imageHeight: imageHeight)
            let rect = MediaPipeSSDRectTransform.rect(
                from: projected, imageWidth: imageWidth, imageHeight: imageHeight,
                rotationKeypoints: Self.rotationKeypoints, targetAngleRadians: Self.targetAngleRadians,
                rectScale: Self.rectScale
            )

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
            let binaryURL = Bundle.module.url(forResource: "MediaPipeFaceDetector_weights", withExtension: "bin", subdirectory: "Models/Pose"),
            let manifestURL = Bundle.module.url(forResource: "MediaPipeFaceDetector_weights", withExtension: "json", subdirectory: "Models/Pose"),
            let opsURL = Bundle.module.url(forResource: "MediaPipeFaceDetector_ops", withExtension: "json", subdirectory: "Models/Pose")
        else
        {
            throw FabricError(.execution(.failed), severity: .recoverable, message: "Could not find bundled MediaPipeFaceDetector graph resources")
        }

        let model = try MediaPipeTFLiteMPSGraph(
            weightsBinaryURL: binaryURL, weightsManifestURL: manifestURL, opsJSONURL: opsURL,
            inputWidth: Self.detectSize, inputHeight: Self.detectSize,
            commandQueue: commandQueue
        )
        Self.cachedModel = model
        return model
    }
}
