//
//  MediaPipeCropPreprocessor.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Encodes a rotated crop + normalize directly from a FabricImage texture
/// into an NHWC float32 buffer — no CVPixelBuffer, no Vision, no CPU-side
/// pixel copy. The output buffer is `.storageModeShared` (genuinely unified
/// CPU/GPU memory on Apple Silicon) and fed directly into
/// MediaPipeTFLiteMPSGraph as an MPSGraphTensorData, the same "GPU writes
/// directly into the model's input buffer" approach RTMPoseInputPreprocessor
/// uses. Deliberately avoids the VNImageRequestHandler / CVPixelBuffer-
/// wrapping overhead profiled as a real bottleneck earlier in this pose work.
///
/// `outputPixelRange` is fixed per instance (not per call), since a given
/// preprocessor is always paired with one model: BlazePalm/BlazeFace's
/// landmark models both normalize to [0,1], but BlazeFace's *detector*
/// normalizes to [-1,1] — confirmed against each model's own
/// ImageToTensorCalculatorOptions.output_tensor_float_range, not assumed
/// from BlazePalm's convention.
final class MediaPipeCropPreprocessor
{
    private struct Uniforms
    {
        var centerPixels: simd_float2
        var rectSizePixels: simd_float2
        var rotationRadians: Float
        var textureTransform: simd_float4x4
        var presentationSizePixels: simd_float2
        var outputSize: simd_uint2
        var outputPixelRange: simd_float2
    }

    private let outputWidth: Int
    private let outputHeight: Int
    private let outputPixelRange: simd_float2
    private let pipeline: MTLComputePipelineState
    private let outputBuffer: MTLBuffer

    init(device: MTLDevice, outputWidth: Int, outputHeight: Int, outputPixelRange: (min: Float, max: Float) = (0, 1)) throws
    {
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.outputPixelRange = simd_float2(outputPixelRange.min, outputPixelRange.max)

        let compiler = MetalFileCompiler(watch: false)
        guard
            let shaderURL = Bundle.module.url(
                forResource: "MediaPipeCropPreprocess",
                withExtension: "metal",
                subdirectory: "Compute/Pose"
            ),
            let source = try? compiler.parse(shaderURL),
            let library = try? device.makeLibrary(source: source, options: nil),
            let function = library.makeFunction(name: "cropRotateAndNormalizeNHWC")
        else {
            throw FabricError(
                .execution(.gpu),
                severity: .recoverable,
                message: "Could not load MediaPipe crop preprocessing kernel"
            )
        }

        self.pipeline = try device.makeComputePipelineState(function: function)

        let byteCount = outputWidth * outputHeight * 3 * MemoryLayout<Float>.stride
        guard let outputBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared) else
        {
            throw FabricError(.execution(.outOfMemory), severity: .recoverable, message: "Could not allocate MediaPipe crop buffer")
        }
        outputBuffer.label = "MediaPipe crop NHWC \(outputWidth)x\(outputHeight)"
        self.outputBuffer = outputBuffer
    }

    /// Convenience entry point for callers that want preprocessing as its
    /// own submission (the synchronous run() path). The asynchronous
    /// submit() path uses the command-buffer overload below so preprocessing
    /// and MPSGraph inference share one submission with no intermediate
    /// wait — see the MediaPipe nodes' useAsynchronousInference toggle.
    func encode(
        image: FabricImage,
        centerNormalizedBottomLeft: simd_float2,
        sizeNormalized: simd_float2,
        rotationRadians: Float,
        commandQueue: MTLCommandQueue
    ) throws -> MTLBuffer
    {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create MediaPipe crop command buffer")
        }

        let outputBuffer = try self.encode(
            image: image,
            centerNormalizedBottomLeft: centerNormalizedBottomLeft,
            sizeNormalized: sizeNormalized,
            rotationRadians: rotationRadians,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return outputBuffer
    }

    /// `centerNormalizedBottomLeft`/`sizeNormalized` are in Fabric's usual
    /// bottom-left-origin, normalized [0,1] convention; `rotationRadians`
    /// is MediaPipeSSDDetectorDecoder.computeRotation's own convention
    /// (top-left/Y-down, independent of the coordinate's origin choice —
    /// see that type's doc comment). Encodes onto `commandBuffer` without
    /// committing, so MPSGraph inference can be appended to the same
    /// command buffer (the async submit() path) — the caller is
    /// responsible for committing (and, for the sync path above, waiting).
    func encode(
        image: FabricImage,
        centerNormalizedBottomLeft: simd_float2,
        sizeNormalized: simd_float2,
        rotationRadians: Float,
        commandBuffer: MTLCommandBuffer
    ) throws -> MTLBuffer
    {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create MediaPipe crop compute pass")
        }

        let presentationSize = image.presentationSize
        let presentationWidth = Float(presentationSize.width)
        let presentationHeight = Float(presentationSize.height)

        // Only the coordinate flips (bottom-left -> top-left); rotation is
        // already in the shader's native convention.
        let centerYTopLeft = 1 - centerNormalizedBottomLeft.y
        var uniforms = Uniforms(
            centerPixels: simd_float2(centerNormalizedBottomLeft.x * presentationWidth, centerYTopLeft * presentationHeight),
            rectSizePixels: simd_float2(sizeNormalized.x * presentationWidth, sizeNormalized.y * presentationHeight),
            rotationRadians: rotationRadians,
            textureTransform: image.textureTransform,
            presentationSizePixels: simd_float2(presentationWidth, presentationHeight),
            outputSize: simd_uint2(UInt32(self.outputWidth), UInt32(self.outputHeight)),
            outputPixelRange: self.outputPixelRange
        )

        encoder.label = "MediaPipe crop, rotate, and normalize"
        encoder.setComputePipelineState(self.pipeline)
        encoder.setTexture(image.texture, index: 0)
        encoder.setBuffer(self.outputBuffer, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        let threadgroupWidth = self.pipeline.threadExecutionWidth
        let threadgroupHeight = max(1, min(8, self.pipeline.maxTotalThreadsPerThreadgroup / threadgroupWidth))
        encoder.dispatchThreads(
            MTLSize(width: self.outputWidth, height: self.outputHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadgroupWidth, height: threadgroupHeight, depth: 1)
        )
        encoder.endEncoding()

        return self.outputBuffer
    }
}
