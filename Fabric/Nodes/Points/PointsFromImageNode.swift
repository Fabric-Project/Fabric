//
//  PointsFromImageNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

/// One point per pixel, or per Step pixels, on the GPU: placed across the image's aspect, colored by
/// it, and pushed toward the camera by its brightness times Depth.
public final class PointsFromImageNode: BaseGPUPointsNode
{
    override public class var name: String { "Points from Image" }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Makes one point per pixel, or every Step pixels, on the GPU. Points lie across the image's aspect, 2 high, take its colors, and move toward the camera by brightness times Depth." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "The image to sample")),
            ("inputStep", ParameterPort(parameter: IntParameter("Step", 4, .inputfield, "Pixels between points, across and down"))),
            ("inputDepth", ParameterPort(parameter: FloatParameter("Depth", 0, .inputfield, "How far brightness moves each point toward the camera"))),
            ("outputPoints", NodePort<Satin.Points>(name: "Points", kind: .Outlet, description: "One point per sampled pixel, with Color")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputStep: ParameterPort<Int> { port(named: "inputStep") }
    public var inputDepth: ParameterPort<Float> { port(named: "inputDepth") }

    override public var kernelSource: String { Self.imageKernelSource }
    override public var kernelFunctionName: String { "pointsFromImageKernel" }

    override public func inputsChanged() -> Bool
    {
        inputImage.valueDidChange || inputStep.valueDidChange || inputDepth.valueDidChange
    }

    private struct PointsFromImageUniforms
    {
        var count: UInt32
        var columns: UInt32
        var step: UInt32
        var width: UInt32
        var height: UInt32
        var aspect: Float
        var depth: Float
    }

    override public func publish(pipeline: MTLComputePipelineState, executionInfo: GraphExecutionInfo,
                                 commandBuffer: MTLCommandBuffer) throws -> Satin.Points?
    {
        guard let texture = inputImage.value?.texture, texture.width > 0, texture.height > 0 else { return nil }
        let step = max(inputStep.value ?? 4, 1)
        let depth = inputDepth.value ?? 0
        let columns = (texture.width + step - 1) / step
        let rows = (texture.height + step - 1) / step
        let count = columns * rows
        let aspect = Float(texture.width) / Float(texture.height)

        let elementStride = MemoryLayout<simd_float4>.stride
        let positions = try context.gpuAllocator.makeBuffer(length: count * elementStride, memoryClass: .gpuOnly, label: "Image Point Positions")
        let colors = try context.gpuAllocator.makeBuffer(length: count * elementStride, memoryClass: .gpuOnly, label: "Image Point Colors")

        if let encoder = commandBuffer.makeComputeCommandEncoder()
        {
            var uniforms = PointsFromImageUniforms(count: UInt32(count), columns: UInt32(columns), step: UInt32(step),
                                                   width: UInt32(texture.width), height: UInt32(texture.height), aspect: aspect, depth: depth)
            encoder.label = "Points from Image"
            encoder.setTexture(texture, index: 0)
            encoder.setBuffer(positions, offset: 0, index: 0)
            encoder.setBuffer(colors, offset: 0, index: 1)
            encoder.setBytes(&uniforms, length: MemoryLayout<PointsFromImageUniforms>.stride, index: 2)
            Self.dispatchPerPoint(encoder, pipeline: pipeline, count: count)
            encoder.endEncoding()
        }

        let float3Layout = AttributeLayout(scalar: .float32, components: 3, byteOffset: 0, byteStride: elementStride)
        let float4Layout = AttributeLayout(scalar: .float32, components: 4, byteOffset: 0, byteStride: elementStride)
        let bounds = Bounds(min: [-aspect, -1, min(0, depth)], max: [aspect, 1, max(0, depth)])
        return try Satin.Points(attributes: [
            (.position, PublishedAttribute(adopting: positions, layout: float3Layout, count: count)),
            (.color, PublishedAttribute(adopting: colors, layout: float4Layout, count: count)),
        ], topology: .implicit, bounds: .known(bounds))
    }

    private static let imageKernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct PointsFromImageUniforms {
        uint count;
        uint columns;
        uint step;
        uint width;
        uint height;
        float aspect;
        float depth;
    };

    kernel void pointsFromImageKernel(texture2d<float, access::read> image [[texture(0)]],
                                      device float4 *positions [[buffer(0)]],
                                      device float4 *colors [[buffer(1)]],
                                      constant PointsFromImageUniforms &uniforms [[buffer(2)]],
                                      uint id [[thread_position_in_grid]]) {
        if (id >= uniforms.count) { return; }
        const uint2 pixel = uint2(min((id % uniforms.columns) * uniforms.step, uniforms.width - 1),
                                  min((id / uniforms.columns) * uniforms.step, uniforms.height - 1));
        const float4 color = image.read(pixel);
        const float2 uv = (float2(pixel) + 0.5) / float2(uniforms.width, uniforms.height);
        const float brightness = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
        positions[id] = float4((uv.x - 0.5) * 2.0 * uniforms.aspect, (0.5 - uv.y) * 2.0, brightness * uniforms.depth, 1.0);
        colors[id] = color;
    }
    """
}
