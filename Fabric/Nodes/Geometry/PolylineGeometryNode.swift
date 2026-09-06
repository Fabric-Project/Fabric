//
//  PolylineGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/3/25.
//

import Satin
import Foundation
import simd
import Metal

/// Tessellates an ordered polyline of 3D points into a triangulated ribbon
/// mesh with joins and caps (see `Satin.PolylineGeometry`, backed by
/// SatinCore's `generatePolylineGeometryData`). Works with any existing
/// Material through the generic `MeshNode`; pair with `LineMaterialNode` for
/// camera-facing/resolution-independent rendering.
public class PolylineGeometryNode : BaseGeometryNode
{
    public override class var name: String { "Polyline Geometry" }
    public override class var nodeDescription: String { "Tessellates a polyline of 3D points into a triangulated ribbon mesh with joins and caps." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        // Inherits inputPrimitiveType (default "Triangle") unchanged — the
        // ribbon's index buffer is always a triangle list, and Triangle is
        // already its correct value; BaseGeometryNode.evaluate reads this port
        // unconditionally, so it must stay registered under the same name.
        let ports = super.registerPorts(context: context)

        return [
            ("inputPoints", NodePort<ContiguousArray<simd_float3>>(name: "Points", kind: .Inlet, description: "Ordered polyline points (XYZ) to tessellate into a thick-line ribbon")),
            ("inputClosed", ParameterPort(parameter: BoolParameter("Closed", false, .button, "When enabled, connects the last point back to the first with no end caps"))),
            ("inputWidth", ParameterPort(parameter: FloatParameter("Width", 0.05, .inputfield, "Ribbon width in world units"))),
            ("inputJoinStyle", ParameterPort(parameter: StringParameter("Join Style", "Miter", ["Miter", "Bevel", "Round"], .dropdown, "How adjacent segments meet at interior points"))),
            ("inputCapStyle", ParameterPort(parameter: StringParameter("Cap Style", "Butt", ["Butt", "Square", "Round"], .dropdown, "How the open ends of the ribbon are finished (ignored when Closed)"))),
            ("inputMiterLimit", ParameterPort(parameter: FloatParameter("Miter Limit", 4.0, .inputfield, "Maximum miter length, as a multiple of half-width, before falling back to a bevel join"))),
            ("inputUp", ParameterPort(parameter: Float3Parameter("Up", simd_float3(0, 0, 1), .inputfield, "Reference vector perpendicular to the plane the ribbon's width should offset within; defaults to the Z axis, matching Fabric's XY-plane 2D convention"))),
            ("inputRoundResolution", ParameterPort(parameter: IntParameter("Round Resolution", 8, .inputfield, "Segments used to tessellate round joins and caps"))),
            ("inputSpeedWidthAmount", ParameterPort(parameter: FloatParameter("Speed Width Amount", 0.0, 0.0, 1.0, .slider, "Blends in a width taper driven by local point spacing — 0 disables it (uniform width); 1 is the full effect. Widely-spaced points read as \"fast\", tightly-spaced as \"slow\""))),
            ("inputSpeedWidthMinMultiplier", ParameterPort(parameter: FloatParameter("Speed Width Min", 0.25, 0.0, 2.0, .slider, "Width multiplier applied at the most widely-spaced (\"fastest\") points"))),
            ("inputSpeedWidthMaxMultiplier", ParameterPort(parameter: FloatParameter("Speed Width Max", 1.0, 0.0, 2.0, .slider, "Width multiplier applied at the most tightly-spaced (\"slowest\") points"))),
            ("inputColors", NodePort<ContiguousArray<simd_float4>>(name: "Colors", kind: .Inlet, description: "Optional per-point vertex color (RGBA). Shorter than Points, the last color pads the rest; unconnected, every vertex defaults to opaque white. Read by LineMaterial's colorBlend.")),
        ] + ports
    }

    public var inputPoints: NodePort<ContiguousArray<simd_float3>> { port(named: "inputPoints") }
    public var inputClosed: ParameterPort<Bool> { port(named: "inputClosed") }
    public var inputWidth: ParameterPort<Float> { port(named: "inputWidth") }
    public var inputJoinStyle: ParameterPort<String> { port(named: "inputJoinStyle") }
    public var inputCapStyle: ParameterPort<String> { port(named: "inputCapStyle") }
    public var inputMiterLimit: ParameterPort<Float> { port(named: "inputMiterLimit") }
    public var inputUp: ParameterPort<simd_float3> { port(named: "inputUp") }
    public var inputRoundResolution: ParameterPort<Int> { port(named: "inputRoundResolution") }
    public var inputSpeedWidthAmount: ParameterPort<Float> { port(named: "inputSpeedWidthAmount") }
    public var inputSpeedWidthMinMultiplier: ParameterPort<Float> { port(named: "inputSpeedWidthMinMultiplier") }
    public var inputSpeedWidthMaxMultiplier: ParameterPort<Float> { port(named: "inputSpeedWidthMaxMultiplier") }
    public var inputColors: NodePort<ContiguousArray<simd_float4>> { port(named: "inputColors") }

    public override var geometry: PolylineGeometry { _geometry }

    private lazy var _geometry: PolylineGeometry = {
        let g = PolylineGeometry(context: self.context)
        g.mutability = .dynamicData
        return g
    }()

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputPoints.valueDidChange
            || self.inputClosed.valueDidChange
            || self.inputWidth.valueDidChange
            || self.inputJoinStyle.valueDidChange
            || self.inputCapStyle.valueDidChange
            || self.inputMiterLimit.valueDidChange
            || self.inputUp.valueDidChange
            || self.inputRoundResolution.valueDidChange
            || self.inputSpeedWidthAmount.valueDidChange
            || self.inputSpeedWidthMinMultiplier.valueDidChange
            || self.inputSpeedWidthMaxMultiplier.valueDidChange
            || self.inputColors.valueDidChange
        {
            let points = self.inputPoints.value ?? []

            self._geometry.update(
                points: points.count >= 2 ? points : [],
                closed: self.inputClosed.value ?? false,
                width: self.inputWidth.value ?? 0.05,
                joinStyle: Self.joinStyle(from: self.inputJoinStyle.value),
                capStyle: Self.capStyle(from: self.inputCapStyle.value),
                miterLimit: self.inputMiterLimit.value ?? 4.0,
                up: self.inputUp.value ?? simd_float3(0, 0, 1),
                roundResolution: self.inputRoundResolution.value ?? 8,
                speedWidthAmount: self.inputSpeedWidthAmount.value ?? 0.0,
                speedWidthMinMultiplier: self.inputSpeedWidthMinMultiplier.value ?? 0.25,
                speedWidthMaxMultiplier: self.inputSpeedWidthMaxMultiplier.value ?? 1.0,
                pointColors: self.inputColors.value
            )
            shouldOutput = true
        }

        return shouldOutput
    }

    private static func joinStyle(from value: String?) -> PolylineJoinStyle
    {
        switch value
        {
        case "Bevel": return .bevel
        case "Round": return .round
        default: return .miter
        }
    }

    private static func capStyle(from value: String?) -> PolylineCapStyle
    {
        switch value
        {
        case "Square": return .square
        case "Round": return .round
        default: return .butt
        }
    }
}
