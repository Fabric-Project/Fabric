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
/// Image in, image out, entirely on the GPU, and structured exactly like
/// ZipDepthNode, the other image-only MPS node: crop-and-normalize, MPSGraph
/// inference and the mask projection are all encoded, in that order, onto
/// Fabric's own shared per-frame command buffer, never a second,
/// independently committed one. `MPSGraphExecutable.encode(to:)` never commits
/// anything on its own -- that's always the caller's explicit choice -- so as
/// long as this node never calls either, its work just sits encoded, in order,
/// alongside everything else, until whoever owns the shared buffer commits it
/// at the end of the frame. That also makes ordering against whatever upstream
/// node most recently wrote `inputImage`'s texture this same frame trivial:
/// same buffer, sequential encode order, no cross-buffer commit-order reasoning
/// needed at all. The mask is read from the model's output buffer by the
/// projection kernel directly, so there is no CPU readback and the result is
/// available downstream in the same frame it was produced. Having no numerical
/// port outputs, it has no synchronous path. See `MediaPipeMPSGraph.encode(...)`.
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

    /// Everything below is built for one variant's resolution and rebuilt
    /// together when the variant changes -- see `prepareModel`.
    private var preparedVariant: ModelVariant?
    private var preprocessor: MediaPipeCropPreprocessor?
    private var maskProjector: MediaPipeSegmentationMaskProjector?
    private var model: MediaPipeMPSGraph?

    /// GPU-only destination for MediaPipeMPSGraph.encode()'s output, read by
    /// the mask projection kernel on the same command buffer. Private, as
    /// nothing on the CPU ever reads it. Reused every frame: the next frame's
    /// write is ordered after this frame's projection by command buffer order.
    private var maskOutputBuffer: MTLBuffer?

    override public func stopExecution(renderer: GraphRenderer) throws
    {
        self.preparedVariant = nil
        self.preprocessor = nil
        self.maskProjector = nil
        self.model = nil
        self.maskOutputBuffer = nil
    }

    public override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        guard self.inputImage.valueDidChange || self.inputModelVariant.valueDidChange || self.isDirty else { return }

        guard let inputImage = self.inputImage.value else
        {
            self.outputSegmentationMask.send(nil)
            return
        }

        let variant = ModelVariant.from(self.inputModelVariant.value)
        try self.prepareModel(for: variant)

        guard let preprocessor, let maskProjector, let model, let maskOutputBuffer else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "MediaPipe Selfie Segmentation model is unavailable")
        }

        let startTime = Date()
        let presentationSize = inputImage.presentationSize
        let outputImage = try renderer.newImage(withWidth: Int(presentationSize.width), height: Int(presentationSize.height))
        outputImage.texture.label = "MediaPipe Selfie Segmentation Mask"

        commandBuffer.pushDebugGroup("MediaPipe Selfie Segmentation")
        defer { commandBuffer.popDebugGroup() }

        let cropBuffer = try preprocessor.encode(
            texture: inputImage.texture,
            textureTransform: inputImage.textureTransform,
            centerNormalizedBottomLeft: MediaPipeSelfieSegmentation.fullFrameCenter,
            sizeNormalized: MediaPipeSelfieSegmentation.fullFrameSize,
            rotationRadians: MediaPipeSelfieSegmentation.noRotation,
            commandBuffer: commandBuffer
        )

        // Drops this frame's mask (never calls outputSegmentationMask.send(), so
        // downstream nodes keep whatever was last sent) instead of blocking if
        // all in-flight slots are already busy -- matches ZipDepthNode and every
        // other MediaPipe node's own no-backlog semantics.
        guard try model.encode(inputBuffer: cropBuffer, outputBuffers: [maskOutputBuffer], commandBuffer: commandBuffer, commit: false) else
        {
            return
        }

        try maskProjector.encode(
            maskBuffer: maskOutputBuffer,
            applySigmoid: MediaPipeSelfieSegmentation.applySigmoid,
            centerNormalizedBottomLeft: MediaPipeSelfieSegmentation.fullFrameCenter,
            sizeNormalized: MediaPipeSelfieSegmentation.fullFrameSize,
            rotationRadians: MediaPipeSelfieSegmentation.noRotation,
            destinationTexture: outputImage.texture,
            commandBuffer: commandBuffer
        )

        // `commandBuffer` is Fabric's shared per-frame buffer -- this node never
        // waits on it, so it's still in flight when execute() returns.
        // GraphRendererTextureCache recycles a managed FabricImage's texture the
        // instant its last Swift reference drops, with no regard for whether the
        // GPU is still using it, so the images must stay alive until this
        // buffer's GPU work actually completes. The model and buffers need the
        // same treatment: `prepareModel` can reassign them on a later frame (a
        // variant change) while this frame's work is still in flight.
        commandBuffer.addCompletedHandler { [inputImage, outputImage, model, cropBuffer, maskOutputBuffer, maskProjector] _ in
            withExtendedLifetime((inputImage, outputImage, model, cropBuffer, maskOutputBuffer, maskProjector)) {}
            MediaPipeInferenceTimingLogger.log(nodeName: Self.name, elapsed: Date().timeIntervalSince(startTime))
        }

        self.outputSegmentationMask.send(outputImage)
    }

    private func prepareModel(for variant: ModelVariant) throws
    {
        guard self.preparedVariant != variant || self.model == nil else { return }

        let model = try Self.mpsGraphModel(for: variant, commandQueue: self.context.commandQueue)
        guard let length = model.outputBufferLengths.first,
              let maskOutputBuffer = self.context.device.makeBuffer(length: length, options: .storageModePrivate)
        else
        {
            throw FabricError(.execution(.outOfMemory), severity: .recoverable, message: "Could not allocate MediaPipe selfie segmentation mask output buffer")
        }
        maskOutputBuffer.label = "MediaPipe Selfie Segmentation Mask Output"

        self.preprocessor = try MediaPipeCropPreprocessor(device: self.context.device, outputWidth: variant.inputWidth, outputHeight: variant.inputHeight)
        // The GPU-resident projection never uses the projector's per-slot CPU
        // scratch buffers, so one is enough.
        self.maskProjector = try MediaPipeSegmentationMaskProjector(device: self.context.device, maskWidth: variant.inputWidth, maskHeight: variant.inputHeight, maxFramesInFlight: 1)
        self.model = model
        self.maskOutputBuffer = maskOutputBuffer
        self.preparedVariant = variant
    }

    private static func mpsGraphModel(for variant: ModelVariant, commandQueue: MTLCommandQueue) throws -> MediaPipeMPSGraph
    {
        try MediaPipeSharedModels.model(named: variant.resourcePrefix, inputWidth: variant.inputWidth, inputHeight: variant.inputHeight, commandQueue: commandQueue)
    }
}
