//
//  ImageToStreamNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import simd

/// One element per pixel, or per Step pixels, on the GPU: the image's colors as a stream, with each
/// sample's texture coordinate, in rows from the top left of the image as it is presented, whatever
/// its stored orientation.
public final class ImageToStreamNode: Node
{
    override public class var name: String { "Image to Stream" }
    override public class var nodeType: Node.NodeType { .Streams }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Samples an image every Step pixels on the GPU into streams: its colors, and each sample's texture coordinate, in rows from the top left. Count is how many samples there are." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "The image to sample")),
            ("inputStep", ParameterPort(parameter: IntParameter("Step", 1, .inputfield, "Pixels between samples, across and down"))),
            ("outputColors", NodePort<GPUStream<simd_float4>>(name: "Colors", kind: .Outlet, description: "One color per sample")),
            ("outputTexcoords", NodePort<GPUStream<simd_float2>>(name: "Texture Coordinates", kind: .Outlet, description: "Each sample's texture coordinate, at its pixel's center")),
            ("outputCount", NodePort<Int>(name: "Count", kind: .Outlet, description: "How many samples each stream holds")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputStep: ParameterPort<Int> { port(named: "inputStep") }
    public var outputColors: NodePort<GPUStream<simd_float4>> { port(named: "outputColors") }
    public var outputTexcoords: NodePort<GPUStream<simd_float2>> { port(named: "outputTexcoords") }
    public var outputCount: NodePort<Int> { port(named: "outputCount") }

    private let kernel = ComputeKernel()
    /// The kernel compiled, so the next execution samples whatever the inputs say.
    private var kernelChanged = true

    override public func enableExecution(renderer: GraphRenderer) throws
    {
        kernel.compile(source: Self.kernelSource, functionNames: ["imageToStreamKernel"], device: context.device)
        kernelChanged = true
        subtitleSubject.send()
        try super.enableExecution(renderer: renderer)
    }

    override public func disableExecution(renderer: GraphRenderer) throws
    {
        kernel.release()
        try super.disableExecution(renderer: renderer)
    }

    override public func deriveStatuses() -> [NodeStatus] { kernel.failure.map { [NodeStatus.error($0)] } ?? [] }

    private struct ImageToStreamUniforms
    {
        var textureTransform: simd_float4x4
        var count: UInt32
        var columns: UInt32
        var step: UInt32
        var width: UInt32
        var height: UInt32
        var storedWidth: UInt32
        var storedHeight: UInt32
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        let kernelJustChanged = kernelChanged
        kernelChanged = false
        guard kernelJustChanged || inputImage.valueDidChange || inputStep.valueDidChange else { return }

        guard let pipeline = kernel.pipelines?.first,
              let image = inputImage.value, image.texture.width > 0, image.texture.height > 0
        else
        {
            outputColors.send(nil)
            outputTexcoords.send(nil)
            outputCount.send(nil)
            return
        }

        let texture = image.texture
        let presented = image.presentationPixelSize
        let step = max(inputStep.value ?? 1, 1)
        let columns = (presented.width + step - 1) / step
        let rows = (presented.height + step - 1) / step
        let count = columns * rows

        let colors = try context.gpuAllocator.makeBuffer(length: count * MemoryLayout<simd_float4>.stride, memoryClass: .gpuOnly, label: "Image Stream Colors")
        let texcoords = try context.gpuAllocator.makeBuffer(length: count * MemoryLayout<simd_float2>.stride, memoryClass: .gpuOnly, label: "Image Stream Texcoords")

        // Fresh buffers hold nothing until the kernel runs, so with no encoder nothing is published.
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Unable to encode Image to Stream")
        }
        do
        {
            var uniforms = ImageToStreamUniforms(textureTransform: image.textureTransform,
                                                 count: UInt32(count), columns: UInt32(columns), step: UInt32(step),
                                                 width: UInt32(presented.width), height: UInt32(presented.height),
                                                 storedWidth: UInt32(texture.width), storedHeight: UInt32(texture.height))
            encoder.label = "Image to Stream"
            encoder.setTexture(texture, index: 0)
            encoder.setBuffer(colors, offset: 0, index: 0)
            encoder.setBuffer(texcoords, offset: 0, index: 1)
            encoder.setBytes(&uniforms, length: MemoryLayout<ImageToStreamUniforms>.stride, index: 2)
            BaseGPUPointsNode.dispatchPerPoint(encoder, pipeline: pipeline, count: count)
            encoder.endEncoding()
        }

        let colorAttribute = PublishedAttribute(adopting: colors,
                                                layout: AttributeLayout(scalar: .float32, components: 4, byteOffset: 0, byteStride: MemoryLayout<simd_float4>.stride),
                                                count: count)
        let texcoordAttribute = PublishedAttribute(adopting: texcoords,
                                                   layout: AttributeLayout(scalar: .float32, components: 2, byteOffset: 0, byteStride: MemoryLayout<simd_float2>.stride),
                                                   count: count)
        outputColors.send(try GPUStream(attribute: colorAttribute), force: true)
        outputTexcoords.send(try GPUStream(attribute: texcoordAttribute), force: true)
        outputCount.send(count)
    }

    private static let kernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    \(FabricImage.presentationSamplingSource)

    // width and height are the image's as presented; storedWidth and storedHeight its texture's.
    struct ImageToStreamUniforms {
        float4x4 textureTransform;
        uint count;
        uint columns;
        uint step;
        uint width;
        uint height;
        uint storedWidth;
        uint storedHeight;
    };

    kernel void imageToStreamKernel(texture2d<float, access::read> image [[texture(0)]],
                                    device float4 *colors [[buffer(0)]],
                                    device float2 *texcoords [[buffer(1)]],
                                    constant ImageToStreamUniforms &uniforms [[buffer(2)]],
                                    uint id [[thread_position_in_grid]]) {
        if (id >= uniforms.count) { return; }
        const uint2 pixel = uint2(min((id % uniforms.columns) * uniforms.step, uniforms.width - 1),
                                  min((id / uniforms.columns) * uniforms.step, uniforms.height - 1));
        const float2 uv = (float2(pixel) + 0.5) / float2(uniforms.width, uniforms.height);
        colors[id] = image.read(fabricStoredPixel(uv, uniforms.textureTransform, uint2(uniforms.storedWidth, uniforms.storedHeight)));
        texcoords[id] = uv;
    }
    """
}
