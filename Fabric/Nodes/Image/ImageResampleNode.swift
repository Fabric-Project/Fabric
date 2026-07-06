//
//  ImageResampleNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin

public final class ImageResampleNode: Node
{
    private enum ResamplingMethod: String, CaseIterable
    {
        case nearest = "Nearest"
        case bilinear = "Bilinear"
        case bicubic = "Bicubic (Catmull-Rom)"
        case lanczos2 = "Lanczos 2"
        case lanczos3 = "Lanczos 3"
        case area = "Area"

        var shaderValue: UInt32
        {
            switch self {
            case .nearest: 0
            case .bilinear: 1
            case .bicubic: 2
            case .lanczos2: 3
            case .lanczos3: 4
            case .area: 5
            }
        }

        var usesSeparableFiltering: Bool
        {
            switch self {
            case .nearest, .bilinear: false
            case .bicubic, .lanczos2, .lanczos3, .area: true
            }
        }
    }

    override public class var name: String { "Image Resample" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .BaseEffect) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String {
        "Resizes an image using nearest, bilinear, bicubic, Lanczos, or area filtering."
    }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            (
                "inputImage",
                NodePort<FabricImage>(
                    name: "Image",
                    kind: .Inlet,
                    description: "Image to resize"
                )
            ),
            (
                "inputWidth",
                ParameterPort(
                    parameter: IntParameter(
                        "Width",
                        0,
                        0,
                        16_384,
                        .inputfield,
                        "Output width in pixels; zero preserves the input width"
                    )
                )
            ),
            (
                "inputHeight",
                ParameterPort(
                    parameter: IntParameter(
                        "Height",
                        0,
                        0,
                        16_384,
                        .inputfield,
                        "Output height in pixels; zero preserves the input height"
                    )
                )
            ),
            (
                "inputMethod",
                ParameterPort(
                    parameter: StringParameter(
                        "Method",
                        ResamplingMethod.bilinear.rawValue,
                        ResamplingMethod.allCases.map(\.rawValue),
                        .dropdown,
                        "Reconstruction filter used while resizing"
                    )
                )
            ),
            (
                "outputImage",
                NodePort<FabricImage>(
                    name: "Image",
                    kind: .Outlet,
                    description: "Resampled image"
                )
            ),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputWidth: ParameterPort<Int> { port(named: "inputWidth") }
    public var inputHeight: ParameterPort<Int> { port(named: "inputHeight") }
    public var inputMethod: ParameterPort<String> { port(named: "inputMethod") }
    public var outputImage: NodePort<FabricImage> { port(named: "outputImage") }

    private var nearestPipeline: MTLComputePipelineState?
    private var bilinearPipeline: MTLComputePipelineState?
    private var horizontalPipeline: MTLComputePipelineState?
    private var verticalPipeline: MTLComputePipelineState?

    public required init(context: Context)
    {
        super.init(context: context)
        setupComputePipelines()
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        setupComputePipelines()
    }

    private func setupComputePipelines()
    {
        let compiler = MetalFileCompiler(watch: false)

        guard
            let shaderURL = Bundle.module.url(
                forResource: "ImageResample",
                withExtension: "metal",
                subdirectory: "Compute/Resample"
            ),
            let source = try? compiler.parse(shaderURL),
            let library = try? context.device.makeLibrary(source: source, options: nil)
        else {
            return
        }

        self.nearestPipeline = makePipeline(named: "resampleNearest", library: library)
        self.bilinearPipeline = makePipeline(named: "resampleBilinear", library: library)
        self.horizontalPipeline = makePipeline(named: "resampleHorizontal", library: library)
        self.verticalPipeline = makePipeline(named: "resampleVertical", library: library)
    }

    private func makePipeline(named name: String,
                              library: MTLLibrary) -> MTLComputePipelineState?
    {
        guard let function = library.makeFunction(name: name) else { return nil }
        return try? context.device.makeComputePipelineState(function: function)
    }

    private struct ResamplingUniforms
    {
        var method: UInt32
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard
            inputImage.valueDidChange
                || inputWidth.valueDidChange
                || inputHeight.valueDidChange
                || inputMethod.valueDidChange
        else {
            return
        }

        guard let sourceImage = inputImage.value else {
            outputImage.send(nil)
            return
        }

        let sourceTexture = sourceImage.texture
        let outputWidth = resolvedDimension(inputWidth.value, fallback: sourceTexture.width)
        let outputHeight = resolvedDimension(inputHeight.value, fallback: sourceTexture.height)
        let method = ResamplingMethod(rawValue: inputMethod.value ?? "") ?? .bilinear

        guard outputWidth != sourceTexture.width || outputHeight != sourceTexture.height else {
            outputImage.send(sourceImage)
            return
        }

        guard
            let destinationImage = renderer.newImage(
                withWidth: outputWidth,
                height: outputHeight,
                format: sourceTexture.pixelFormat
            ),
            let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else {
            outputImage.send(nil)
            return
        }

        destinationImage.texture.label = "Image Resample \(outputWidth)×\(outputHeight)"
        computeEncoder.label = "Image Resample – \(method.rawValue)"

        let didEncode: Bool
        if method.usesSeparableFiltering {
            didEncode = encodeSeparableResampling(
                method: method,
                sourceTexture: sourceTexture,
                destinationTexture: destinationImage.texture,
                renderer: renderer,
                computeEncoder: computeEncoder
            )
        }
        else {
            didEncode = encodeDirectResampling(
                method: method,
                sourceTexture: sourceTexture,
                destinationTexture: destinationImage.texture,
                computeEncoder: computeEncoder
            )
        }

        computeEncoder.endEncoding()
        guard didEncode else {
            outputImage.send(nil)
            return
        }

        destinationImage.isFlipped = sourceImage.isFlipped
        outputImage.send(destinationImage)
    }

    private func resolvedDimension(_ requestedDimension: Int?, fallback: Int) -> Int
    {
        let value = requestedDimension ?? 0
        return value > 0 ? min(value, 16_384) : fallback
    }

    private func encodeDirectResampling(method: ResamplingMethod,
                                        sourceTexture: MTLTexture,
                                        destinationTexture: MTLTexture,
                                        computeEncoder: MTLComputeCommandEncoder) -> Bool
    {
        let pipeline = method == .nearest ? nearestPipeline : bilinearPipeline
        guard let pipeline else { return false }

        computeEncoder.setComputePipelineState(pipeline)
        computeEncoder.setTexture(sourceTexture, index: 0)
        computeEncoder.setTexture(destinationTexture, index: 1)
        dispatch(
            computeEncoder,
            pipeline: pipeline,
            width: destinationTexture.width,
            height: destinationTexture.height
        )
        return true
    }

    private func encodeSeparableResampling(method: ResamplingMethod,
                                           sourceTexture: MTLTexture,
                                           destinationTexture: MTLTexture,
                                           renderer: GraphRenderer,
                                           computeEncoder: MTLComputeCommandEncoder) -> Bool
    {
        guard let horizontalPipeline, let verticalPipeline else { return false }

        var uniforms = ResamplingUniforms(method: method.shaderValue)
        computeEncoder.setBytes(
            &uniforms,
            length: MemoryLayout<ResamplingUniforms>.stride,
            index: 0
        )

        if sourceTexture.width == destinationTexture.width {
            encodeVerticalPass(
                sourceTexture: sourceTexture,
                destinationTexture: destinationTexture,
                pipeline: verticalPipeline,
                computeEncoder: computeEncoder
            )
            return true
        }

        if sourceTexture.height == destinationTexture.height {
            encodeHorizontalPass(
                sourceTexture: sourceTexture,
                destinationTexture: destinationTexture,
                pipeline: horizontalPipeline,
                computeEncoder: computeEncoder
            )
            return true
        }

        guard let intermediateImage = renderer.newImage(
            withWidth: destinationTexture.width,
            height: sourceTexture.height,
            format: sourceTexture.pixelFormat
        ) else {
            return false
        }
        intermediateImage.texture.label = "Image Resample Horizontal Intermediate"

        encodeHorizontalPass(
            sourceTexture: sourceTexture,
            destinationTexture: intermediateImage.texture,
            pipeline: horizontalPipeline,
            computeEncoder: computeEncoder
        )
        computeEncoder.memoryBarrier(scope: .textures)
        encodeVerticalPass(
            sourceTexture: intermediateImage.texture,
            destinationTexture: destinationTexture,
            pipeline: verticalPipeline,
            computeEncoder: computeEncoder
        )
        return true
    }

    private func encodeHorizontalPass(sourceTexture: MTLTexture,
                                      destinationTexture: MTLTexture,
                                      pipeline: MTLComputePipelineState,
                                      computeEncoder: MTLComputeCommandEncoder)
    {
        computeEncoder.setComputePipelineState(pipeline)
        computeEncoder.setTexture(sourceTexture, index: 0)
        computeEncoder.setTexture(destinationTexture, index: 1)
        dispatch(
            computeEncoder,
            pipeline: pipeline,
            width: destinationTexture.width,
            height: destinationTexture.height
        )
    }

    private func encodeVerticalPass(sourceTexture: MTLTexture,
                                    destinationTexture: MTLTexture,
                                    pipeline: MTLComputePipelineState,
                                    computeEncoder: MTLComputeCommandEncoder)
    {
        computeEncoder.setComputePipelineState(pipeline)
        computeEncoder.setTexture(sourceTexture, index: 0)
        computeEncoder.setTexture(destinationTexture, index: 1)
        dispatch(
            computeEncoder,
            pipeline: pipeline,
            width: destinationTexture.width,
            height: destinationTexture.height
        )
    }

    private func dispatch(_ computeEncoder: MTLComputeCommandEncoder,
                          pipeline: MTLComputePipelineState,
                          width: Int,
                          height: Int)
    {
        let threadgroupWidth = pipeline.threadExecutionWidth
        let threadgroupHeight = max(
            1,
            min(8, pipeline.maxTotalThreadsPerThreadgroup / threadgroupWidth)
        )

        computeEncoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: threadgroupWidth,
                height: threadgroupHeight,
                depth: 1
            )
        )
    }
}
