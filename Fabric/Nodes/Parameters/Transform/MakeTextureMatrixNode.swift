//
//  MakeTextureMatrixNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class MakeTextureMatrixNode : Node
{
    override public class var name: String { "Make Texture Matrix" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Builds a 4x4 affine UV transform (texture matrix) from pan, scale, rotation and pivot. Applied to an output UV, the matrix returns the source UV to sample. Scale is the UV multiplier: scale (1, 1) is identity; scale (0.5, 0.5) samples half the source (2x magnified); scale (2, 2) samples double (zoomed out). Rotation is in degrees and pivots around Pivot; Pan translates after rotation and scale. Pivot (0.5, 0.5) anchors to the UV centre." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPan", ParameterPort(parameter: Float2Parameter("Pan", .zero, .inputfield, "UV translation (X, Y) applied after scale and rotation"))),
            ("inputScale", ParameterPort(parameter: Float2Parameter("Scale", simd_float2(1, 1), .inputfield, "UV scale factor (X, Y). 1 is identity; smaller than 1 magnifies, larger than 1 samples a larger source region."))),
            ("inputRotation", ParameterPort(parameter: FloatParameter("Rotation (degrees)", 0.0, .inputfield, "UV rotation around Pivot in degrees"))),
            ("inputPivot", ParameterPort(parameter: Float2Parameter("Pivot", simd_float2(0.5, 0.5), .inputfield, "Fixed point in UV space around which scale and rotation are applied. (0.5, 0.5) is the UV centre."))),
            ("outputMatrix", NodePort<simd_float4x4>(name: "Texture Matrix", kind: .Outlet, description: "Resulting 4x4 UV transform")),
        ]
    }

    public var inputPan: ParameterPort<simd_float2> { port(named: "inputPan") }
    public var inputScale: ParameterPort<simd_float2> { port(named: "inputScale") }
    public var inputRotation: ParameterPort<Float> { port(named: "inputRotation") }
    public var inputPivot: ParameterPort<simd_float2> { port(named: "inputPivot") }
    public var outputMatrix: NodePort<simd_float4x4> { port(named: "outputMatrix") }

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

        self.outputMatrix.send(Self.textureMatrix(pan: pan, scale: scale, rotationDegrees: rotationDegrees, pivot: pivot))
    }

    /// Composes a 4x4 UV affine transform embedding a 2D
    /// rotate+scale+translate around `pivot`, with `pan` applied after.
    /// Acting on `(u, v, 0, 1)`: returns the source UV to sample.
    static func textureMatrix(pan: simd_float2, scale: simd_float2, rotationDegrees: Float, pivot: simd_float2) -> simd_float4x4
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
