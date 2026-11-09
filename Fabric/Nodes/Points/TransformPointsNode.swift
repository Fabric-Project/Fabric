//
//  TransformPointsNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

/// Moves points by a transform on the GPU: positions, and normals when they have them, are
/// published new; every other attribute is shared with the input as it is.
public final class TransformPointsNode: BaseGPUPointsNode
{
    override public class var name: String { "Transform Points" }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Moves points by a transform on the GPU. Positions, and normals when there are any, are published new; every other attribute is shared with the input." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputPoints", NodePort<Satin.Points>(name: "Points", kind: .Inlet, description: "The points to move")),
            ("inputTransform", PortType.Transform.makeFreshPort(name: "Transform", kind: .Inlet, description: "The transform applied to every point")),
            ("outputPoints", NodePort<Satin.Points>(name: "Points", kind: .Outlet, description: "The moved points")),
        ]
    }

    public var inputPoints: NodePort<Satin.Points> { port(named: "inputPoints") }
    public var inputTransform: NodePort<simd_float4x4> { port(named: "inputTransform") }

    override public var kernelSource: String { Self.transformKernelSource }
    override public var kernelFunctionName: String { "transformPointsKernel" }

    override public func inputsChanged() -> Bool { inputPoints.valueDidChange || inputTransform.valueDidChange }

    override public func publish(pipeline: MTLComputePipelineState, executionInfo: GraphExecutionInfo,
                                 commandBuffer: MTLCommandBuffer) throws -> Satin.Points?
    {
        guard let points = inputPoints.value else { return nil }
        return try transformed(points, by: inputTransform.value ?? matrix_identity_float4x4, pipeline: pipeline, commandBuffer: commandBuffer)
    }

    private func transformed(_ points: Satin.Points, by transform: simd_float4x4, pipeline: MTLComputePipelineState,
                             commandBuffer: MTLCommandBuffer) throws -> Satin.Points
    {
        let upperLeft = simd_float3x3(simd_make_float3(transform.columns.0), simd_make_float3(transform.columns.1), simd_make_float3(transform.columns.2))
        let normalMatrix = upperLeft.inverse.transpose
        let normalTransform = simd_float4x4(simd_make_float4(normalMatrix.columns.0), simd_make_float4(normalMatrix.columns.1),
                                            simd_make_float4(normalMatrix.columns.2), [0, 0, 0, 1])

        var attributes: [(PointAttribute, PublishedAttribute)] = []
        for (key, attribute) in points.attributes
        {
            switch key
            {
            case .position:
                attributes.append((key, try transformed(attribute, by: transform, isDirection: false, pipeline: pipeline, commandBuffer: commandBuffer)))
            case .normal:
                attributes.append((key, try transformed(attribute, by: normalTransform, isDirection: true, pipeline: pipeline, commandBuffer: commandBuffer)))
            default:
                attributes.append((key, attribute))
            }
        }

        let bounds: PointsBounds
        switch points.bounds
        {
        case let .known(known): bounds = .known(transformBounds(known, transform))
        case .unknown: bounds = .unknown
        }
        return try Satin.Points(attributes: attributes, topology: points.topology, bounds: bounds)
    }

    private struct TransformPointsUniforms
    {
        var matrix: simd_float4x4
        var count: UInt32
        var byteStride: UInt32
        var byteOffset: UInt32
        var isDirection: UInt32
    }

    /// A new attribute of `attribute`'s first three floats moved by `matrix`, as float3s padded to 16 bytes.
    private func transformed(_ attribute: PublishedAttribute, by matrix: simd_float4x4, isDirection: Bool,
                             pipeline: MTLComputePipelineState, commandBuffer: MTLCommandBuffer) throws -> PublishedAttribute
    {
        let layout = attribute.layout
        guard layout.scalar == .float32, layout.components >= 3, layout.byteStride % 4 == 0, layout.byteOffset % 4 == 0 else
        {
            throw FabricError(.execution(.failed), severity: .recoverable,
                              message: "Transform Points moves float positions and normals of three or four components.")
        }

        let count = attribute.count
        let outputStride = MemoryLayout<simd_float4>.stride
        let output = try context.gpuAllocator.makeBuffer(length: max(count, 1) * outputStride, memoryClass: .gpuOnly, label: "Transformed Points")
        if count > 0, let encoder = commandBuffer.makeComputeCommandEncoder()
        {
            var uniforms = TransformPointsUniforms(matrix: matrix, count: UInt32(count), byteStride: UInt32(layout.byteStride),
                                                   byteOffset: UInt32(layout.byteOffset), isDirection: isDirection ? 1 : 0)
            encoder.label = "Transform Points"
            encoder.setBuffer(attribute.buffer, offset: 0, index: 0)
            encoder.setBuffer(output, offset: 0, index: 1)
            encoder.setBytes(&uniforms, length: MemoryLayout<TransformPointsUniforms>.stride, index: 2)
            Self.dispatchPerPoint(encoder, pipeline: pipeline, count: count)
            encoder.endEncoding()
        }
        return PublishedAttribute(adopting: output,
                                  layout: AttributeLayout(scalar: .float32, components: 3, byteOffset: 0, byteStride: outputStride),
                                  count: count)
    }

    private static let transformKernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct TransformPointsUniforms {
        float4x4 matrix;
        uint count;
        uint byteStride;
        uint byteOffset;
        uint isDirection;
    };

    kernel void transformPointsKernel(device const uchar *source [[buffer(0)]],
                                      device float4 *destination [[buffer(1)]],
                                      constant TransformPointsUniforms &uniforms [[buffer(2)]],
                                      uint id [[thread_position_in_grid]]) {
        if (id >= uniforms.count) { return; }
        device const float *value = (device const float *)(source + uniforms.byteOffset + id * uniforms.byteStride);
        if (uniforms.isDirection != 0) {
            const float3 direction = (uniforms.matrix * float4(value[0], value[1], value[2], 0.0)).xyz;
            destination[id] = float4(normalize(direction), 0.0);
        } else {
            destination[id] = float4((uniforms.matrix * float4(value[0], value[1], value[2], 1.0)).xyz, 1.0);
        }
    }
    """
}
