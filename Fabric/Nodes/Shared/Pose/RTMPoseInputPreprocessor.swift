//
//  RTMPoseInputPreprocessor.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Encodes RTMPose crop, scale, RGB conversion, and ImageNet normalization
/// directly from a FabricImage texture into an NCHW float32 Metal buffer.
final class RTMPoseInputPreprocessor
{
    private struct Uniforms
    {
        var regionOrigin: simd_float2
        var regionSize: simd_float2
        var textureTransform: simd_float4x4
        var outputSize: simd_uint2
    }

    private let outputWidth: Int
    private let outputHeight: Int
    private let pipeline: MTLComputePipelineState
    private let outputBuffer: MTLBuffer

    init(device: MTLDevice, outputWidth: Int, outputHeight: Int) throws
    {
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight

        let compiler = MetalFileCompiler(watch: false)
        guard
            let shaderURL = Bundle.module.url(
                forResource: "RTMPoseInputPreprocess",
                withExtension: "metal",
                subdirectory: "Compute/Pose"
            ),
            let source = try? compiler.parse(shaderURL),
            let library = try? device.makeLibrary(source: source, options: nil),
            let function = library.makeFunction(name: "cropScaleAndNormalizePlanarRGB")
        else {
            throw FabricError(
                .execution(.gpu),
                severity: .recoverable,
                message: "Could not load RTMPose input preprocessing kernel"
            )
        }

        self.pipeline = try device.makeComputePipelineState(function: function)

        let byteCount = 3 * outputWidth * outputHeight * MemoryLayout<Float>.stride
        guard let outputBuffer = device.makeBuffer(length: byteCount, options: .storageModePrivate) else
        {
            throw FabricError(
                .execution(.outOfMemory),
                severity: .recoverable,
                message: "Could not allocate RTMPose input buffer"
            )
        }
        outputBuffer.label = "RTMPose normalized planar RGB \(outputWidth)x\(outputHeight)"
        self.outputBuffer = outputBuffer
    }

    /// Convenience entry point for callers that want preprocessing as its own
    /// submission. The asynchronous inference path uses the command-buffer
    /// overload below so preprocessing and MPSGraph share one submission.
    func encode(image: FabricImage,
                regionOfInterest: simd_float4,
                commandQueue: MTLCommandQueue) throws -> MTLBuffer
    {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else
        {
            throw FabricError(
                .execution(.gpu),
                severity: .recoverable,
                message: "Could not create RTMPose input command buffer"
            )
        }

        let outputBuffer = try self.encode(
            image: image,
            regionOfInterest: regionOfInterest,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        return outputBuffer
    }

    /// Encodes preprocessing without committing, allowing MPSGraph inference
    /// to be appended to the same command buffer.
    func encode(image: FabricImage,
                regionOfInterest: simd_float4,
                commandBuffer: MTLCommandBuffer) throws -> MTLBuffer
    {
        guard regionOfInterest.z > 0, regionOfInterest.w > 0 else
        {
            throw FabricError(
                .execution(.failed),
                severity: .recoverable,
                message: "RTMPose region of interest must have positive dimensions"
            )
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else
        {
            throw FabricError(
                .execution(.gpu),
                severity: .recoverable,
                message: "Could not create RTMPose input compute pass"
            )
        }

        var uniforms = Uniforms(
            regionOrigin: simd_float2(
                regionOfInterest.x,
                1 - regionOfInterest.y - regionOfInterest.w
            ),
            regionSize: simd_float2(regionOfInterest.z, regionOfInterest.w),
            textureTransform: image.textureTransform,
            outputSize: simd_uint2(UInt32(self.outputWidth), UInt32(self.outputHeight))
        )

        encoder.label = "RTMPose crop, scale, and normalize"
        encoder.setComputePipelineState(self.pipeline)
        encoder.setTexture(image.texture, index: 0)
        encoder.setBuffer(self.outputBuffer, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        let threadgroupWidth = self.pipeline.threadExecutionWidth
        let threadgroupHeight = max(
            1,
            min(8, self.pipeline.maxTotalThreadsPerThreadgroup / threadgroupWidth)
        )
        encoder.dispatchThreads(
            MTLSize(width: self.outputWidth, height: self.outputHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: threadgroupWidth,
                height: threadgroupHeight,
                depth: 1
            )
        )
        encoder.endEncoding()
        return self.outputBuffer
    }
}
