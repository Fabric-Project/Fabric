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
/// Standalone comparison path.
///
/// Unlike Face/Hand/Pose, there is no detector, no region, and no aspect-
/// preserving crop -- the whole frame is stretched into the tensor.
///
/// Two model variants: General (256x256), Landscape (256x144), selected by
/// a plain dropdown (switching variant never changes port shape).
///
/// Crop-and-normalize AND MPSGraph inference are both encoded onto Fabric's
/// own shared per-frame command buffer, never a second, independently
/// committed one: `MPSGraphExecutable.encode(to:)` never commits anything on
/// its own -- that's always the caller's explicit choice (`commit()` /
/// `commitAndContinue()`) -- so as long as this node never calls either,
/// its work just sits encoded, in order, alongside everything else, until
/// whoever owns the shared buffer commits it at the end of the frame. That
/// also makes ordering against whatever upstream node most recently wrote
/// `inputImage`'s texture this same frame trivial: same buffer, sequential
/// encode order, no cross-buffer commit-order reasoning needed at all. See
/// `MediaPipeMPSGraph.encode(...)`.
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

    /// Recreated when the active variant's resolution changes.
    private var preprocessor: MediaPipeCropPreprocessor?
    private var preprocessorVariant: ModelVariant?
    private var maskProjector: MediaPipeSegmentationMaskProjector?
    private var maskProjectorVariant: ModelVariant?

    /// GPU-resident destination for MediaPipeMPSGraph.encode()'s output --
    /// .storageModeShared so the completion handler can read it back into
    /// lastMaskLogits without a CPU round-trip through run()/submit().
    private var maskOutputBuffer: MTLBuffer?
    private var maskOutputBufferVariant: ModelVariant?

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
            do { try self.scheduleSegmentation(image: inputImage, variant: variant, commandBuffer: commandBuffer) }
            catch { print("MediaPipeSelfieSegmentationNode: scheduleSegmentation failed: \(error)") }
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

    private func maskOutputBuffer(for variant: ModelVariant, model: MediaPipeMPSGraph) throws -> MTLBuffer
    {
        if let existing = self.maskOutputBuffer, self.maskOutputBufferVariant == variant { return existing }

        guard let length = model.outputBufferLengths.first,
              let buffer = self.context.device.makeBuffer(length: length, options: .storageModeShared)
        else
        {
            throw FabricError(.execution(.outOfMemory), severity: .recoverable, message: "Could not allocate MediaPipe selfie segmentation mask output buffer")
        }
        buffer.label = "MediaPipe Selfie Segmentation Mask Output"
        self.maskOutputBuffer = buffer
        self.maskOutputBufferVariant = variant
        return buffer
    }

    /// Encodes crop-and-normalize AND MPSGraph inference onto Fabric's
    /// shared `commandBuffer`, one after the other -- never a second,
    /// separately created buffer. Neither call commits anything on its own,
    /// so both just sit encoded here, in order, until whoever owns
    /// `commandBuffer` (Fabric's render loop) commits it once at the end of
    /// the frame. lastMaskLogits updates once that whole buffer completes.
    /// Silently drops the cycle (never updates lastMaskLogits) if all
    /// maxFramesInFlight inference slots are already busy, matching
    /// MediaPipeMPSGraph.encode()'s and MediaPipeCropPreprocessor's own
    /// no-backlog semantics.
    private func scheduleSegmentation(image: FabricImage, variant: ModelVariant, commandBuffer: MTLCommandBuffer) throws
    {
        let startTime = Date()
        let preprocessor = try self.preprocessor(for: variant)
        let model = try Self.mpsGraphModel(for: variant, commandQueue: self.context.commandQueue)
        let maskOutputBuffer = try self.maskOutputBuffer(for: variant, model: model)

        let cropBuffer = try preprocessor.encode(
            texture: image.texture,
            textureTransform: image.textureTransform,
            centerNormalizedBottomLeft: MediaPipeSelfieSegmentation.fullFrameCenter,
            sizeNormalized: MediaPipeSelfieSegmentation.fullFrameSize,
            rotationRadians: MediaPipeSelfieSegmentation.noRotation,
            commandBuffer: commandBuffer
        )

        guard try model.encode(inputBuffer: cropBuffer, outputBuffers: [maskOutputBuffer], commandBuffer: commandBuffer) else
        {
            return
        }

        // Keeps `image`/`cropBuffer` out of GraphRendererTextureCache's
        // recycle pool until the GPU work reading them is verified done, not
        // just encoded -- same reasoning as ZipDepthNode's completion-handler
        // lifetime capture. Reads maskOutputBuffer back once the whole
        // shared buffer (crop and inference both) actually completes.
        commandBuffer.addCompletedHandler { [weak self, image, cropBuffer] sharedBuffer in
            withExtendedLifetime((image, cropBuffer)) {}
            guard let self else { return }
            if let error = sharedBuffer.error
            {
                print("MediaPipeSelfieSegmentationNode: segmentation failed: \(error)")
                return
            }
            let count = maskOutputBuffer.length / MemoryLayout<Float>.stride
            let logits = Array(UnsafeBufferPointer(
                start: maskOutputBuffer.contents().assumingMemoryBound(to: Float.self),
                count: count
            ))
            MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
            self.lastMaskLogits = logits
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
