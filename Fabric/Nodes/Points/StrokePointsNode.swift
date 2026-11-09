//
//  StrokePointsNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import simd

/// Strokes points into ribbons on the GPU, with no readback, so points a GPU pass wrote stroke as
/// readily as ones built from arrays. Draw the result with Points Geometry set to Triangle.
public final class StrokePointsNode: BaseGPUPointsNode
{
    override public class var name: String { "Stroke Points" }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Strokes points into ribbons on the GPU, one per strip, with joins and caps. Sizes multiply the width and Colors carry along. Outputs triangles: draw them with Points Geometry set to Triangle, with any material." }

    private static let joinTitles = ["Miter", "Bevel", "Round"]
    private static let capTitles = ["Butt", "Square", "Round"]

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputPoints", NodePort<Satin.Points>(name: "Points", kind: .Inlet, description: "The points to stroke, along their strips")),
            ("inputWidth", ParameterPort(parameter: FloatParameter("Width", 0.1, .inputfield, "Ribbon width in world units"))),
            ("inputJoin", ParameterPort(parameter: StringParameter("Join", "Round", Self.joinTitles, .dropdown, "The shape where two segments meet"))),
            ("inputCap", ParameterPort(parameter: StringParameter("Cap", "Round", Self.capTitles, .dropdown, "The shape at each end of an open strip"))),
            ("inputMiterLimit", ParameterPort(parameter: FloatParameter("Miter Limit", 4, .inputfield, "How far a Miter join may reach, in half-widths, before it becomes a Bevel"))),
            ("inputRoundResolution", ParameterPort(parameter: IntParameter("Round Segments", 8, .inputfield, "Segments in each round join and cap"))),
            ("inputClosed", ParameterPort(parameter: BoolParameter("Close All", false, .button, "When enabled, every strip returns to its first point"))),
            ("outputPoints", NodePort<Satin.Points>(name: "Triangles", kind: .Outlet, description: "The ribbons as a triangle list, with normals, texture coordinates and colors")),
        ]
    }

    public var inputPoints: NodePort<Satin.Points> { port(named: "inputPoints") }
    public var inputWidth: ParameterPort<Float> { port(named: "inputWidth") }
    public var inputJoin: ParameterPort<String> { port(named: "inputJoin") }
    public var inputCap: ParameterPort<String> { port(named: "inputCap") }
    public var inputMiterLimit: ParameterPort<Float> { port(named: "inputMiterLimit") }
    public var inputRoundResolution: ParameterPort<Int> { port(named: "inputRoundResolution") }
    public var inputClosed: ParameterPort<Bool> { port(named: "inputClosed") }

    override public var kernelSource: String { GPUStrokeTessellation.source }
    override public var kernelFunctionName: String { GPUStrokeTessellation.functionName }

    override public func inputsChanged() -> Bool
    {
        inputPoints.valueDidChange || inputWidth.valueDidChange || inputJoin.valueDidChange || inputCap.valueDidChange
            || inputMiterLimit.valueDidChange || inputRoundResolution.valueDidChange || inputClosed.valueDidChange
    }

    override public func publish(pipeline: MTLComputePipelineState, executionInfo: GraphExecutionInfo,
                                 commandBuffer: MTLCommandBuffer) throws -> Satin.Points?
    {
        guard let points = inputPoints.value else { return nil }
        let style = Stroke.Style(width: inputWidth.value ?? 0.1,
                                 join: Stroke.Join(rawValue: Int32(Self.joinTitles.firstIndex(of: inputJoin.value ?? "") ?? 2)) ?? .round,
                                 cap: Stroke.Cap(rawValue: Int32(Self.capTitles.firstIndex(of: inputCap.value ?? "") ?? 2)) ?? .round,
                                 miterLimit: inputMiterLimit.value ?? 4,
                                 roundResolution: inputRoundResolution.value ?? 8)
        do
        {
            return try GPUStrokeTessellation.encode(points: points, style: style, closesAll: inputClosed.value ?? false,
                                                    pipeline: pipeline, commandBuffer: commandBuffer, allocator: context.gpuAllocator)
        }
        catch GPUStrokeTessellation.TessellationError.unsupportedLayout(let attribute)
        {
            throw FabricError(.execution(.failed), severity: .recoverable,
                              message: "Stroke Points can't read these points' \(attribute) attribute: it needs floats.")
        }
    }
}
