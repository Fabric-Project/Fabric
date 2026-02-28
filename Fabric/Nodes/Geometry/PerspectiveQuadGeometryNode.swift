//
//  PerspectiveQuadGeometryNode.swift
//  Fabric
//
//  Created by Toby Harris on 2/28/26.
//

import Satin
import Foundation
import simd
import Metal

#if SWIFT_PACKAGE
import SatinCore
#endif

public class PerspectiveQuadGeometry: SatinGeometry
{
    public var topLeft: simd_float2 = simd_float2(-0.5, 0.5) {
        didSet { if oldValue != topLeft { _updateData = true } }
    }
    public var topRight: simd_float2 = simd_float2(0.5, 0.5) {
        didSet { if oldValue != topRight { _updateData = true } }
    }
    public var bottomLeft: simd_float2 = simd_float2(-0.5, -0.5) {
        didSet { if oldValue != bottomLeft { _updateData = true } }
    }
    public var bottomRight: simd_float2 = simd_float2(0.5, -0.5) {
        didSet { if oldValue != bottomRight { _updateData = true } }
    }
    public var resolution: Int32 = 10 {
        didSet { if oldValue != resolution { _updateData = true } }
    }

    override public func generateGeometryData() -> GeometryData {
        let res = max(Int32(1), resolution)
        let resF = Float(res)
        let perRow = res + 1
        let vertices = Int(perRow * perRow)
        let triangles = Int(res * res * 2)

        let vtx = UnsafeMutablePointer<SatinVertex>(
            OpaquePointer(malloc(vertices * MemoryLayout<SatinVertex>.size))
        )!
        let ind = UnsafeMutablePointer<TriangleIndices>(
            OpaquePointer(malloc(triangles * MemoryLayout<TriangleIndices>.size))
        )!

        let tl3 = simd_float3(topLeft.x, topLeft.y, 0)
        let tr3 = simd_float3(topRight.x, topRight.y, 0)
        let bl3 = simd_float3(bottomLeft.x, bottomLeft.y, 0)
        let br3 = simd_float3(bottomRight.x, bottomRight.y, 0)

        // Iterate bottom-to-top (y=0 at bottom = bottomLeft row)
        // to match PlaneGeometry's vertex/UV layout
        var vertexIndex: Int = 0
        var triangleIndex: Int = 0

        for y in 0...res {
            let yf = Float(y)
            let vNorm = yf / resF  // 0 at bottom, 1 at top

            for x in 0...res {
                let xf = Float(x)
                let uNorm = xf / resF  // 0 at left, 1 at right

                // Bilinear interpolation: vNorm=0 → bottom row, vNorm=1 → top row
                let bottom = bl3 + (br3 - bl3) * uNorm
                let top    = tl3 + (tr3 - tl3) * uNorm
                let pos    = bottom + (top - bottom) * vNorm

                // Normal from tangent cross product
                let dPdu = (br3 - bl3) * (1 - vNorm) + (tr3 - tl3) * vNorm
                let dPdv = (tl3 - bl3) * (1 - uNorm) + (tr3 - br3) * uNorm
                var normal = simd_normalize(simd_cross(dPdu, dPdv))
                if normal.x.isNaN { normal = simd_float3(0, 0, 1) }

                vtx[vertexIndex] = SatinVertex(
                    position: pos,
                    normal: normal,
                    uv: simd_float2(uNorm, vNorm)
                )
                vertexIndex += 1

                // Indices — same winding as PlaneGeometry (CCW from +z)
                if y < res, x < res {
                    let bl = UInt32(x + y * perRow)
                    let br = bl + 1
                    let tl = UInt32(x + (y + 1) * perRow)
                    let tr = tl + 1

                    ind[triangleIndex] = TriangleIndices(i0: bl, i1: br, i2: tl)
                    triangleIndex += 1
                    ind[triangleIndex] = TriangleIndices(i0: br, i1: tr, i2: tl)
                    triangleIndex += 1
                }
            }
        }

        return GeometryData(
            vertexCount: Int32(vertices),
            vertexData: vtx,
            indexCount: Int32(triangles),
            indexData: ind
        )
    }
}

public class PerspectiveQuadGeometryNode : BaseGeometryNode
{
    public override class var name: String { "Perspective Quad Geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return [
            ("inputTopLeft",     ParameterPort(parameter: Float2Parameter("Top Left",     simd_float2(-0.5,  0.5), .inputfield, "Top-left corner position"))),
            ("inputTopRight",    ParameterPort(parameter: Float2Parameter("Top Right",    simd_float2( 0.5,  0.5), .inputfield, "Top-right corner position"))),
            ("inputBottomLeft",  ParameterPort(parameter: Float2Parameter("Bottom Left",  simd_float2(-0.5, -0.5), .inputfield, "Bottom-left corner position"))),
            ("inputBottomRight", ParameterPort(parameter: Float2Parameter("Bottom Right", simd_float2( 0.5, -0.5), .inputfield, "Bottom-right corner position"))),
            ("inputResolution",  ParameterPort(parameter: IntParameter("Resolution", 10, .inputfield, "Number of subdivision segments"))),
        ] + ports
    }

    // Proxy Ports
    public var inputTopLeft:     ParameterPort<simd_float2> { port(named: "inputTopLeft") }
    public var inputTopRight:    ParameterPort<simd_float2> { port(named: "inputTopRight") }
    public var inputBottomLeft:  ParameterPort<simd_float2> { port(named: "inputBottomLeft") }
    public var inputBottomRight: ParameterPort<simd_float2> { port(named: "inputBottomRight") }
    public var inputResolution:  ParameterPort<Int>         { port(named: "inputResolution") }

    public override var geometry: SatinGeometry { _geometry }

    private let _geometry = PerspectiveQuadGeometry()

    override public func evaluate(geometry: SatinGeometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        guard let geo = geometry as? PerspectiveQuadGeometry else { return shouldOutputGeometry }

        if self.inputTopLeft.valueDidChange, let v = self.inputTopLeft.value {
            geo.topLeft = v
            shouldOutputGeometry = true
        }
        if self.inputTopRight.valueDidChange, let v = self.inputTopRight.value {
            geo.topRight = v
            shouldOutputGeometry = true
        }
        if self.inputBottomLeft.valueDidChange, let v = self.inputBottomLeft.value {
            geo.bottomLeft = v
            shouldOutputGeometry = true
        }
        if self.inputBottomRight.valueDidChange, let v = self.inputBottomRight.value {
            geo.bottomRight = v
            shouldOutputGeometry = true
        }
        if self.inputResolution.valueDidChange, let v = self.inputResolution.value {
            geo.resolution = Int32(v)
            shouldOutputGeometry = true
        }

        return shouldOutputGeometry
    }
}
