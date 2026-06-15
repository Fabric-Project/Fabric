//
//  OrientationArrayFromAxisAngleNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class OrientationArrayFromAxisAngleNode : Node
{
    public override class var name: String { "Orientation Array From Axis Angle" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Converts per-element Axes and Angles (degrees) into an array of quaternion orientations. Inputs are zipped per element; output length matches the longer, the shorter padding with its last element (so a single-element array broadcasts as a constant). Axes are normalized; a zero axis yields identity." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputAxes", NodePort<ContiguousArray<simd_float3>>(name: "Axes", kind: .Inlet, description: "Per-element rotation axis (will be normalized)")),
            ("inputAngles", NodePort<ContiguousArray<Float>>(name: "Angles", kind: .Inlet, description: "Per-element rotation angle in degrees")),
            ("outputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Per-element quaternion orientation (X, Y, Z, W)")),
        ]
    }

    public var inputAxes: NodePort<ContiguousArray<simd_float3>> { port(named: "inputAxes") }
    public var inputAngles: NodePort<ContiguousArray<Float>> { port(named: "inputAngles") }
    public var outputOrientations: NodePort<ContiguousArray<simd_float4>> { port(named: "outputOrientations") }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputAxes.valueDidChange || self.inputAngles.valueDidChange else { return }

        let axesIn = self.inputAxes.value
        let anglesIn = self.inputAngles.value

        let count = [axesIn?.count ?? 0, anglesIn?.count ?? 0].max() ?? 0
        guard count > 0 else {
            self.outputOrientations.send(ContiguousArray<simd_float4>())
            return
        }

        let axes = (axesIn ?? []).paddedToLast(count: count, fallback: simd_float3(0, 1, 0))
        let angles = (anglesIn ?? []).paddedToLast(count: count, fallback: 0)

        var output = ContiguousArray<simd_float4>()
        output.reserveCapacity(count)
        for i in 0..<count {
            output.append(simd_quatf(axis: axes[i], angleDegrees: angles[i]).vector)
        }
        self.outputOrientations.send(output)
    }
}
