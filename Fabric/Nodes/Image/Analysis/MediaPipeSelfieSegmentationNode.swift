//
//  MediaPipeSelfieSegmentationNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd
import MPSMediaPipe

/// Runs MediaPipe's Selfie Segmentation model (person-vs-background mask).
/// Standalone comparison path, same sync/async toggle every other
/// MediaPipe node here uses.
///
/// Unlike Face/Hand/Pose, there is no detector, no region, and no aspect-
/// preserving crop -- the whole frame is stretched into the tensor.
///
/// Two model variants: General (256x256), Landscape (256x144), selected by
/// a plain dropdown (switching variant never changes port shape).
public class MediaPipeSelfieSegmentationNode: Node
{
    override public class var name: String { "MediaPipe Selfie Segmentation" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Segments the prominent person in frame using MediaPipe's Selfie Segmentation model, via MPSGraph (test/comparison path). No detector or region — the whole frame is stretched directly into the model." }

    private typealias ModelVariant = MediaPipeSelfieSegmentation.Variant

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to segment")),
            ("inputModelVariant", ParameterPort(parameter: StringParameter("Model Variant", ModelVariant.general.rawValue, ModelVariant.allCases.map(\.rawValue), .dropdown, "General (256x256) or Landscape (256x144, faster, tuned for wide framing)"))),

            ("outputSegmentationMask", NodePort<FabricImage>(name: "Segmentation Mask", kind: .Outlet, description: "Per-pixel person-segmentation confidence (sigmoid-activated), full image space, RGB-replicated with alpha 1. Not temporally smoothed.")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputModelVariant: ParameterPort<String> { port(named: "inputModelVariant") }
    public var outputSegmentationMask: NodePort<FabricImage> { port(named: "outputSegmentationMask") }

    private static var cachedModels: [ModelVariant: MediaPipeMPSGraph] = [:]
    private static let modelLock = NSLock()

    /// Not a Setting yet -- plain toggle while the async path is validated.
    private static let useAsynchronousInference = false

    /// Recreated when the active variant's resolution changes.
    private var preprocessor: MediaPipeCropPreprocessor?
    private var preprocessorVariant: ModelVariant?
    private var maskProjector: MediaPipeSegmentationMaskProjector?
    private var maskProjectorVariant: ModelVariant?

    private let lastMaskLogitsLock = NSLock()
    private var lastMaskLogitsStorage: [Float] = []
    /// Backed by a lock because, under the async path, the GPU completion
    /// callback writes this from a thread other than execute()'s.
    private var lastMaskLogits: [Float]
    {
        get
        {
            self.lastMaskLogitsLock.lock()
            defer { self.lastMaskLogitsLock.unlock() }
            return self.lastMaskLogitsStorage
        }
        set
        {
            self.lastMaskLogitsLock.lock()
            self.lastMaskLogitsStorage = newValue
            self.lastMaskLogitsLock.unlock()
        }
    }

    public override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        let variant = ModelVariant.from(self.inputModelVariant.value)

        if self.inputImage.valueDidChange, let inputImage = self.inputImage.value
        {
            if Self.useAsynchronousInference
            {
                do { try self.submitSegment(image: inputImage, variant: variant) }
                catch { print("MediaPipeSelfieSegmentationNode: submitSegment failed: \(error)") }
            }
            else
            {
                do { self.lastMaskLogits = try self.segment(image: inputImage, variant: variant) }
                catch { print("MediaPipeSelfieSegmentationNode: segment failed: \(error)") }
            }
        }

        guard let inImage = self.inputImage.value else { return }

        let maskLogits = self.lastMaskLogits
        guard maskLogits.isEmpty == false else { return }

        do
        {
            let projector = try self.maskProjector(for: variant)
            let presentationSize = inImage.presentationSize
            let outImage = try renderer.newImage(withWidth: Int(presentationSize.width), height: Int(presentationSize.height))

            try projector.encode(
                maskValues: maskLogits,
                applySigmoid: MediaPipeSelfieSegmentation.applySigmoid,
                centerNormalizedBottomLeft: MediaPipeSelfieSegmentation.fullFrameCenter,
                sizeNormalized: MediaPipeSelfieSegmentation.fullFrameSize,
                rotationRadians: MediaPipeSelfieSegmentation.noRotation,
                destinationTexture: outImage.texture,
                commandBuffer: commandBuffer
            )

            self.outputSegmentationMask.send(outImage)
        }
        catch { print("MediaPipeSelfieSegmentationNode: mask projection failed: \(error)") }
    }

    private func preprocessor(for variant: ModelVariant) throws -> MediaPipeCropPreprocessor
    {
        if let existing = self.preprocessor, self.preprocessorVariant == variant { return existing }
        let created = try MediaPipeCropPreprocessor(device: self.context.device, outputWidth: variant.inputWidth, outputHeight: variant.inputHeight)
        self.preprocessor = created
        self.preprocessorVariant = variant
        return created
    }

    private func maskProjector(for variant: ModelVariant) throws -> MediaPipeSegmentationMaskProjector
    {
        if let existing = self.maskProjector, self.maskProjectorVariant == variant { return existing }
        let created = try MediaPipeSegmentationMaskProjector(device: self.context.device, maskWidth: variant.inputWidth, maskHeight: variant.inputHeight)
        self.maskProjector = created
        self.maskProjectorVariant = variant
        return created
    }

    private func segment(image: FabricImage, variant: ModelVariant) throws -> [Float]
    {
        let startTime = Date()
        let preprocessor = try self.preprocessor(for: variant)
        let model = try Self.mpsGraphModel(for: variant, commandQueue: self.context.commandQueue)

        let inputBuffer = try preprocessor.encode(
            texture: image.texture,
            textureTransform: image.textureTransform,
            centerNormalizedBottomLeft: MediaPipeSelfieSegmentation.fullFrameCenter,
            sizeNormalized: MediaPipeSelfieSegmentation.fullFrameSize,
            rotationRadians: MediaPipeSelfieSegmentation.noRotation,
            commandQueue: self.context.commandQueue
        )

        let outputs = model.run(inputBuffer: inputBuffer)
        MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
        return outputs.first ?? []
    }

    /// Async counterpart of segment(): encodes stretch+inference onto one
    /// command buffer without waiting, updating lastMaskLogits from the
    /// completion callback once the GPU finishes. Silently drops the frame
    /// (never updates lastMaskLogits) if all in-flight slots are busy,
    /// matching segment()'s no-backlog semantics -- now N-deep instead of
    /// single-flight (see MediaPipeCropPreprocessor's maxFramesInFlight).
    private func submitSegment(image: FabricImage, variant: ModelVariant) throws
    {
        let startTime = Date()
        let preprocessor = try self.preprocessor(for: variant)
        let model = try Self.mpsGraphModel(for: variant, commandQueue: self.context.commandQueue)

        guard let commandBuffer = self.context.commandQueue.makeCommandBuffer() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create asynchronous MediaPipe selfie segmentation command buffer")
        }

        let inputBuffer = try preprocessor.encode(
            texture: image.texture,
            textureTransform: image.textureTransform,
            centerNormalizedBottomLeft: MediaPipeSelfieSegmentation.fullFrameCenter,
            sizeNormalized: MediaPipeSelfieSegmentation.fullFrameSize,
            rotationRadians: MediaPipeSelfieSegmentation.noRotation,
            commandBuffer: commandBuffer
        )

        model.submit(inputBuffer: inputBuffer, commandBuffer: commandBuffer) { [weak self, image] result in
            guard let self else { return }
            switch result
            {
            case .success(let outputs):
                MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
                self.lastMaskLogits = outputs.first ?? []
            case .failure(let error):
                print("MediaPipeSelfieSegmentationNode: async inference failed: \(error)")
            }
        }
    }

    private static func mpsGraphModel(for variant: ModelVariant, commandQueue: MTLCommandQueue) throws -> MediaPipeMPSGraph
    {
        Self.modelLock.lock()
        defer { Self.modelLock.unlock() }

        if let existing = Self.cachedModels[variant] { return existing }

        let model = try MediaPipeMPSGraph.loadBundled(
            named: variant.resourcePrefix,
            inputWidth: variant.inputWidth, inputHeight: variant.inputHeight,
            commandQueue: commandQueue
        )
        Self.cachedModels[variant] = model
        return model
    }
}
