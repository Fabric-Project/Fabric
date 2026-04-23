//
//  TransformFromPSRPNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class TransformFromPSRPNode : Node
{
    override public class var name: String { "Transform From PSRP" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Builds a 2D affine transform from pan, scale, rotation and pivot, packed as a 4x4 matrix. When applied to a point (x, y, 0, 1), returns the transformed point. Scale is the coordinate multiplier: scale (1, 1) is identity. Rotation is in degrees and pivots around Pivot; Pan translates after rotation and scale. Pivot (0.5, 0.5) anchors to the unit-square centre." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPan", ParameterPort(parameter: Float2Parameter("Pan", .zero, .inputfield, "Translation (X, Y) applied after scale and rotation"))),
            ("inputScale", ParameterPort(parameter: Float2Parameter("Scale", simd_float2(1, 1), .inputfield, "Scale factor (X, Y). 1 is identity."))),
            ("inputRotation", ParameterPort(parameter: FloatParameter("Rotation (degrees)", 0.0, .inputfield, "Rotation around Pivot in degrees"))),
            ("inputPivot", ParameterPort(parameter: Float2Parameter("Pivot", simd_float2(0.5, 0.5), .inputfield, "Fixed point around which scale and rotation are applied. (0.5, 0.5) anchors to the unit-square centre."))),
            ("outputTransform", NodePort<simd_float4x4>(name: "Transform", kind: .Outlet, description: "Resulting 2D affine transform as a 4x4 matrix")),
        ]
    }

    public var inputPan: ParameterPort<simd_float2> { port(named: "inputPan") }
    public var inputScale: ParameterPort<simd_float2> { port(named: "inputScale") }
    public var inputRotation: ParameterPort<Float> { port(named: "inputRotation") }
    public var inputPivot: ParameterPort<simd_float2> { port(named: "inputPivot") }
    public var outputTransform: NodePort<simd_float4x4> { port(named: "outputTransform") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputPan.valueDidChange
            || self.inputScale.valueDidChange
            || self.inputRotation.valueDidChange
            || self.inputPivot.valueDidChange
        else { return }

        let pan = self.inputPan.value ?? .zero
        let scale = self.inputScale.value ?? simd_float2(1, 1)
        let rotationDegrees = self.inputRotation.value ?? 0
        let pivot = self.inputPivot.value ?? simd_float2(0.5, 0.5)

        self.outputTransform.send(Self.affineTransform(pan: pan, scale: scale, rotationDegrees: rotationDegrees, pivot: pivot))
    }

    /// Composes a 2D affine transform (packed in a 4x4 matrix) embedding a
    /// rotate+scale+translate around `pivot`, with `pan` applied after.
    /// Acting on `(x, y, 0, 1)`: returns the transformed point.
    static func affineTransform(pan: simd_float2, scale: simd_float2, rotationDegrees: Float, pivot: simd_float2) -> simd_float4x4
    {
        let theta = rotationDegrees * .pi / 180.0
        let c = cos(theta)
        let s = sin(theta)

        // 2x2 rotation * scale
        let a =  scale.x * c
        let b =  scale.x * s
        let cc = -scale.y * s
        let d =  scale.y * c

        // Translation so that M(pivot) = pivot + pan (pivot is a fixed point).
        let tx = pivot.x + pan.x - (a * pivot.x + cc * pivot.y)
        let ty = pivot.y + pan.y - (b * pivot.x + d * pivot.y)

        // Column-major 4x4. 2D affine embedded in the XY plane; Z passes through.
        return simd_float4x4(
            simd_float4(a,  b,  0, 0),
            simd_float4(cc, d,  0, 0),
            simd_float4(0,  0,  1, 0),
            simd_float4(tx, ty, 0, 1)
        )
    }
}
