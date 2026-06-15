//
//  RingPointsNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class RingPointsNode : Node
{
    public override class var name: String { "Ring Points" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Generates N points evenly spaced around a ring. The Orientation quaternion rotates a canonical local frame (ring lies in local XY, θ=0 along local +X, normal +Z) into world space. Identity orientation places the ring in the XY plane. Arc less than 360° produces an arc centred about θ=0." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputCount", ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of points to emit"))),
            ("inputRadius", ParameterPort(parameter: FloatParameter("Radius", 1.0, 0.0, 1000.0, .inputfield, "Distance from ring centre"))),
            ("inputArcDegrees", ParameterPort(parameter: FloatParameter("Arc (degrees)", 360.0, 0.0, 360.0, .inputfield, "Angular sweep. 360 gives a full ring."))),
            ("inputOrientation", ParameterPort(parameter: Float4Parameter("Up Orientation", simd_float4(0, 0, 0, 1), .inputfield, "Quaternion rotating the canonical frame (ring in local XY, +X=θ=0, +Z=normal) into world space. Same format as the Look At node's Up Orientation, so one source can drive both."))),
            ("outputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Outlet, description: "Array of per-point world-space positions")),
        ]
    }

    public var inputCount: ParameterPort<Int> { port(named: "inputCount") }
    public var inputRadius: ParameterPort<Float> { port(named: "inputRadius") }
    public var inputArcDegrees: ParameterPort<Float> { port(named: "inputArcDegrees") }
    public var inputOrientation: ParameterPort<simd_float4> { port(named: "inputOrientation") }
    public var outputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "outputPositions") }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputCount.valueDidChange
            || self.inputRadius.valueDidChange
            || self.inputArcDegrees.valueDidChange
            || self.inputOrientation.valueDidChange
        else { return }

        let count = max(0, self.inputCount.value ?? 0)
        guard count > 0 else {
            self.outputPositions.send(ContiguousArray<simd_float3>())
            return
        }

        let radius = max(0.0, self.inputRadius.value ?? 1.0)
        let arcRads = (self.inputArcDegrees.value ?? 360.0) * Float.pi / 180.0
        let orientation = simd_quatf(vector: self.inputOrientation.value ?? simd_float4(0, 0, 0, 1)).normalized

        // The orientation is constant across all points, so resolve the ring's
        // local X/Y axes into world space once; each point is then a linear
        // combination of them.
        let basis = matrix_float3x3(orientation)
        let xAxis = basis.columns.0
        let yAxis = basis.columns.1

        let step = arcRads / Float(count)
        var theta = -arcRads * 0.5 + step * 0.5

        var output = ContiguousArray<simd_float3>()
        output.reserveCapacity(count)
        for _ in 0..<count {
            output.append((radius * cos(theta)) * xAxis + (radius * sin(theta)) * yAxis)
            theta += step
        }
        self.outputPositions.send(output)
    }
}
