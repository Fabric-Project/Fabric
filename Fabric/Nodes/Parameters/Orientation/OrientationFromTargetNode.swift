//
//  OrientationFromTargetNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// Single-value look-at: orients local +Z from Position toward Target, with
/// roll resolved against Up Orientation, then post-multiplied by Aim Offset.
/// The array equivalent is OrientationArrayFromTargetNode.
public class OrientationFromTargetNode : Node
{
    override public class var name: String { "Orientation From Target" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Quaternion) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Produces a quaternion whose local +Z axis points from Position toward Target, with roll resolved against Up Orientation, then post-multiplied by Aim Offset. Up Orientation's local +Z is the up reference (identity gives world +Z). Aim Offset re-aims in the look frame: identity looks at the Target, 180° looks away. Position coincident with Target maps to identity." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPosition", ParameterPort(parameter: Float3Parameter("Position", simd_float3(0, 0, 0), .inputfield, "Viewpoint position (XYZ)"))),
            ("inputTarget", ParameterPort(parameter: Float3Parameter("Target", simd_float3(0, 0, 1), .inputfield, "World-space target to face (XYZ)"))),
            ("inputUpOrientation", ParameterPort(parameter: Float4Parameter("Up Orientation", simd_float4(0, 0, 0, 1), .inputfield, "Roll reference; local +Z is the up direction (identity gives world +Z). Quaternion (X, Y, Z, W)"))),
            ("inputAimOffset", ParameterPort(parameter: Float4Parameter("Aim Offset", simd_float4(0, 0, 0, 1), .inputfield, "Rotation in the look frame after aiming (identity looks at, 180° looks away). Quaternion (X, Y, Z, W)"))),
            ("outputOrientation", NodePort<simd_float4>(name: "Orientation", kind: .Outlet, description: "Quaternion orientation (X, Y, Z, W)")),
        ]
    }

    public var inputPosition: ParameterPort<simd_float3> { port(named: "inputPosition") }
    public var inputTarget: ParameterPort<simd_float3> { port(named: "inputTarget") }
    public var inputUpOrientation: ParameterPort<simd_float4> { port(named: "inputUpOrientation") }
    public var inputAimOffset: ParameterPort<simd_float4> { port(named: "inputAimOffset") }
    public var outputOrientation: NodePort<simd_float4> { port(named: "outputOrientation") }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPosition.valueDidChange
            || self.inputTarget.valueDidChange
            || self.inputUpOrientation.valueDidChange
            || self.inputAimOffset.valueDidChange
        else { return }

        let position = self.inputPosition.value ?? simd_float3(0, 0, 0)
        let target = self.inputTarget.value ?? simd_float3(0, 0, 1)
        let up = simd_quatf.upDirection(from: self.inputUpOrientation.value ?? simd_float4(0, 0, 0, 1))
        let offset = simd_quatf(safeVector: self.inputAimOffset.value ?? simd_float4(0, 0, 0, 1))

        let look = simd_quatf(lookingAlong: target - position, up: up)
        self.outputOrientation.send((look * offset).vector)
    }
}
