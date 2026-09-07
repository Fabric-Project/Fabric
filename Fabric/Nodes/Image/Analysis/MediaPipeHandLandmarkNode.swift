//
//  MediaPipeHandLandmarkNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Runs MediaPipe's hand landmark model against a caller-supplied region +
/// rotation, via a from-scratch MPSGraph port of the model's own resolved
/// TFLite op graph (see MediaPipeTFLiteMPSGraph.swift) — no CoreML.
/// Standalone comparison test against HandPoseAnalysisNode's RTMPose-based
/// pipeline — not wired into it. Wire MediaPipe Hand Detection's
/// Region/Rotation outputs into this node's matching inputs.
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
            ("inputRegionOfInterest", NodePort<simd_float4>(name: "Region of Interest", kind: .Inlet, description: "Hand region as (x, y, width, height) normalized bottom-left-origin — wire in from MediaPipe Hand Detection's Region output. Defaults to the full frame when unconnected.")),
            ("inputRotation", NodePort<Float>(name: "Rotation", kind: .Inlet, description: "In-plane rotation in radians — wire in from MediaPipe Hand Detection's Rotation output. Defaults to 0 (no rotation) when unconnected.")),

            ("outputThumb", NodePort<ContiguousArray<simd_float2>>(name: "Thumb", kind: .Outlet, description: "Thumb points ordered CMC, MP, IP, Tip in unit coordinates")),
            ("outputIndex", NodePort<ContiguousArray<simd_float2>>(name: "Index", kind: .Outlet, description: "Index finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputMiddle", NodePort<ContiguousArray<simd_float2>>(name: "Middle", kind: .Outlet, description: "Middle finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputRing", NodePort<ContiguousArray<simd_float2>>(name: "Ring", kind: .Outlet, description: "Ring finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputLittle", NodePort<ContiguousArray<simd_float2>>(name: "Little", kind: .Outlet, description: "Little finger points ordered MCP, PIP, DIP, Tip in unit coordinates")),
            ("outputWrist", NodePort<simd_float2>(name: "Wrist", kind: .Outlet, description: "Position of wrist in unit coordinates")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputRegionOfInterest: NodePort<simd_float4> { port(named: "inputRegionOfInterest") }
    public var inputRotation: NodePort<Float> { port(named: "inputRotation") }

    public var outputThumb: NodePort<ContiguousArray<simd_float2>> { port(named: "outputThumb") }
    public var outputIndex: NodePort<ContiguousArray<simd_float2>> { port(named: "outputIndex") }
    public var outputMiddle: NodePort<ContiguousArray<simd_float2>> { port(named: "outputMiddle") }
    public var outputRing: NodePort<ContiguousArray<simd_float2>> { port(named: "outputRing") }
    public var outputLittle: NodePort<ContiguousArray<simd_float2>> { port(named: "outputLittle") }
    public var outputWrist: NodePort<simd_float2> { port(named: "outputWrist") }

    // MediaPipe's own 21-point HAND_CONNECTIONS ordering: 0=wrist,
    // 1-4=thumb, 5-8=index, 9-12=middle, 13-16=ring, 17-20=little.
    private static let thumbIndices = [1, 2, 3, 4]
    private static let indexIndices = [5, 6, 7, 8]
    private static let middleIndices = [9, 10, 11, 12]
    private static let ringIndices = [13, 14, 15, 16]
    private static let littleIndices = [17, 18, 19, 20]
    private static let wristIndex = 0

    private static let fullFrameRegion = simd_float4(0, 0, 1, 1)
    private static let inputSize = 224

    private static var cachedModel: MediaPipeTFLiteMPSGraph?
    private static let modelLock = NSLock()

    /// Not a Setting yet — a plain toggle while the async path is
    /// validated, mirroring HandPoseAnalysisNode's own toggle. false:
    /// synchronous run(), blocks execute() until the GPU finishes. true:
    /// submit(), which encodes crop+inference onto one command buffer
    /// without waiting and updates lastLandmarks from a completion callback
    /// ~1 frame (or more, under load) later.
    private static let useAsynchronousInference = true

    private var preprocessor: MediaPipeHandCropPreprocessor?

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
                try? self.submitLandmarks(image: inputImage, region: region, rotation: rotation)
            }
            else if let hand = try? self.runLandmarks(image: inputImage, region: region, rotation: rotation)
            {
                self.lastLandmarks = hand
            }
        }

        guard let inImage = self.inputImage.value else { return }
        guard self.lastLandmarks.isEmpty == false else { return }

        let aspect = Float(inImage.presentationSize.height / inImage.presentationSize.width)

        self.outputThumb.send(self.unitPoints(at: Self.thumbIndices, aspect: aspect))
        self.outputIndex.send(self.unitPoints(at: Self.indexIndices, aspect: aspect))
        self.outputMiddle.send(self.unitPoints(at: Self.middleIndices, aspect: aspect))
        self.outputRing.send(self.unitPoints(at: Self.ringIndices, aspect: aspect))
        self.outputLittle.send(self.unitPoints(at: Self.littleIndices, aspect: aspect))

        if self.lastLandmarks.indices.contains(Self.wristIndex)
        {
            self.outputWrist.send(self.unitPoint(from: self.lastLandmarks[Self.wristIndex], aspect: aspect))
        }
    }

    private func runLandmarks(image: FabricImage, region: simd_float4, rotation: Float) throws -> [simd_float3]
    {
        let preprocessor = try self.preprocessor ?? MediaPipeHandCropPreprocessor(device: self.context.device, outputWidth: Self.inputSize, outputHeight: Self.inputSize)
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
        let preprocessor = try self.preprocessor ?? MediaPipeHandCropPreprocessor(device: self.context.device, outputWidth: Self.inputSize, outputHeight: Self.inputSize)
        self.preprocessor = preprocessor

        let model = try Self.mpsGraphModel(commandQueue: self.context.commandQueue)

        let center = simd_float2(region.x + region.z / 2, region.y + region.w / 2)
        let size = simd_float2(region.z, region.w)

        guard let commandBuffer = self.context.commandQueue.makeCommandBuffer() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create asynchronous MediaPipe hand landmark command buffer")
        }

        let inputBuffer = try preprocessor.encode(
            image: image,
            centerNormalizedBottomLeft: center,
            sizeNormalized: size,
            rotationRadians: rotation,
            commandBuffer: commandBuffer
        )

        model.submit(inputBuffer: inputBuffer, commandBuffer: commandBuffer) { [weak self] result in
            guard let self, case .success(let outputs) = result else { return }
            self.lastLandmarks = Self.projectLandmarks(outputs: outputs, center: center, size: size, rotation: rotation)
        }
    }

    /// Output order matches MediaPipeTFLiteMPSGraph's graph, which is
    /// TFLiteModule.forward()'s own return order (confirmed identical to
    /// the bundled CoreML models' Identity/Identity_1/Identity_2/
    /// Identity_3, since ct.convert traces that same forward() call):
    /// [landmarks(63), presence(1), handedness(1), world_landmarks(63)].
    private static func projectLandmarks(outputs: [[Float]], center: simd_float2, size: simd_float2, rotation: Float) -> [simd_float3]
    {
        guard outputs.count >= 4 else { return [] }
        let (landmarksRaw, presenceRaw, handednessRaw, worldRaw) = (outputs[0], outputs[1], outputs[2], outputs[3])

        let presence = presenceRaw.first ?? 0
        let handedness = handednessRaw.first ?? 0

        // MediaPipeHandLandmarkProjection's rect.cy is top-left-origin
        // (matching MediaPipeHandRectTransform.handRect's own convention),
        // but `center` above is bottom-left-origin (the preprocessor's own
        // parameter flips it back internally) -- flip here for the
        // projection math, then flip the resulting landmarks' y back to
        // bottom-left-origin below, matching HandPoseAnalysisNode's space.
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

    private static func mpsGraphModel(commandQueue: MTLCommandQueue) throws -> MediaPipeTFLiteMPSGraph
    {
        Self.modelLock.lock()
        defer { Self.modelLock.unlock() }

        if let existing = Self.cachedModel { return existing }

        guard
            let binaryURL = Bundle.module.url(forResource: "MediaPipeHandLandmarks_weights", withExtension: "bin", subdirectory: "Models/Pose"),
            let manifestURL = Bundle.module.url(forResource: "MediaPipeHandLandmarks_weights", withExtension: "json", subdirectory: "Models/Pose"),
            let opsURL = Bundle.module.url(forResource: "MediaPipeHandLandmarks_ops", withExtension: "json", subdirectory: "Models/Pose")
        else
        {
            throw FabricError(.execution(.failed), severity: .recoverable, message: "Could not find bundled MediaPipeHandLandmarks graph resources")
        }

        let model = try MediaPipeTFLiteMPSGraph(
            weightsBinaryURL: binaryURL, weightsManifestURL: manifestURL, opsJSONURL: opsURL,
            inputWidth: Self.inputSize, inputHeight: Self.inputSize,
            commandQueue: commandQueue
        )
        Self.cachedModel = model
        return model
    }

    private func unitPoints(at indices: [Int], aspect: Float) -> ContiguousArray<simd_float2>
    {
        var points = ContiguousArray<simd_float2>()
        points.reserveCapacity(indices.count)

        for index in indices where self.lastLandmarks.indices.contains(index)
        {
            points.append(self.unitPoint(from: self.lastLandmarks[index], aspect: aspect))
        }

        return points
    }

    /// `landmarks` are normalized full-image, bottom-left origin already
    /// (MediaPipeHandLandmarkProjection composes them against a
    /// bottom-left-origin center — see that call site above), matching the
    /// same space HandPoseAnalysisNode's unitPoint expects.
    private func unitPoint(from landmark: simd_float3, aspect: Float) -> simd_float2
    {
        simd_float2(remap(landmark.x, 0.0, 1.0, -1.0, 1.0),
                    remap(landmark.y, 0.0, 1.0, -aspect, aspect))
    }
}
