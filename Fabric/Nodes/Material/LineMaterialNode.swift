//
//  LineMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/3/25.
//

import Foundation
import Satin
import simd
import Metal

/// Shades a `PolylineGeometryNode` ribbon. `inputMode` selects between the
/// CPU-tessellated geometry as-is, a constant screen-space pixel width that
/// faces the camera (Billboard), or true perspective width clamped to a
/// minimum pixel width at a distance (Perspective Min Width) — see
/// `LineMaterial.metal` for the vertex shader that recomputes the offset from
/// the geometry's Custom0/1/2 attributes. `inputColorBlend` mixes the flat
/// `inputColor` toward the geometry's per-point vertex colors (white by
/// default when the Polyline Geometry node's Colors port is unconnected).
public class LineMaterialNode: BaseMaterialNode
{
    public class LineMaterial : SourceMaterial { }

    public override class var name: String { "Line Material" }
    override public class var nodeDescription: String { "Shades a Polyline Geometry ribbon; modes select the CPU-tessellated geometry as-is, a constant screen-space pixel width facing the camera, or true perspective width clamped to a minimum pixel width at a distance." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return [
            ("inputColor", ParameterPort(parameter: Float4Parameter("Color", .one, .zero, .one, .colorpicker, "Flat color applied to the line"))),
            ("inputColorBlend", ParameterPort(parameter: FloatParameter("Vertex Color Blend", 0.0, 0.0, 1.0, .slider, "Blends toward the Polyline Geometry's per-point vertex colors — 0 uses only the flat Color above (the default, matching every vertex defaulting to white when no colors are wired), 1 uses the vertex colors outright"))),
            ("inputMode", ParameterPort(parameter: StringParameter("Mode", "True Geometry", ["True Geometry", "Billboard", "Perspective Min Width"], .dropdown, "How the line's on-screen width is computed"))),
            ("inputPixelWidth", ParameterPort(parameter: FloatParameter("Pixel Width", 4.0, 0.5, 64.0, .slider, "Line width in screen pixels, used by Billboard and Perspective Min Width modes"))),
            ("inputMinPixelWidth", ParameterPort(parameter: FloatParameter("Min Pixel Width", 1.5, 0.5, 64.0, .slider, "Minimum on-screen width in pixels the line is allowed to shrink to in Perspective Min Width mode"))),
        ] + ports
    }

    public var inputColor: ParameterPort<simd_float4> { port(named: "inputColor") }
    public var inputColorBlend: ParameterPort<Float> { port(named: "inputColorBlend") }
    public var inputMode: ParameterPort<String> { port(named: "inputMode") }
    public var inputPixelWidth: ParameterPort<Float> { port(named: "inputPixelWidth") }
    public var inputMinPixelWidth: ParameterPort<Float> { port(named: "inputMinPixelWidth") }

    public override var material: LineMaterial {
        return _material
    }

    private var _material: LineMaterial

    required public init(context: Context)
    {
        // Bundle(for:) cannot see SPM package resources; Bundle.module owns them.
        let shaderURL = Bundle.module.url(forResource: "LineMaterial", withExtension: "metal", subdirectory: "Materials")

        self._material = LineMaterial(context: context, pipelineURL: shaderURL!)

        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        guard let context = decoder.context?.documentContext as? Context else { fatalError("Invalid Context") }

        let shaderURL = Bundle.module.url(forResource: "LineMaterial", withExtension: "metal", subdirectory: "Materials")

        self._material = LineMaterial(context: context, pipelineURL: shaderURL!)

        try super.init(from: decoder)
    }

    override public func evaluate(material: Material, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(material: material, atTime: atTime)

        if self.inputColor.valueDidChange,
           let color = self.inputColor.value
        {
            self.material.set("color", color)
            shouldOutput = true
        }

        if self.inputColorBlend.valueDidChange,
           let colorBlend = self.inputColorBlend.value
        {
            self.material.set("colorBlend", colorBlend)
            shouldOutput = true
        }

        if self.inputMode.valueDidChange
        {
            self.material.set("mode", Self.modeValue(from: self.inputMode.value))
            shouldOutput = true
        }

        if self.inputPixelWidth.valueDidChange,
           let pixelWidth = self.inputPixelWidth.value
        {
            self.material.set("pixelWidth", pixelWidth)
            shouldOutput = true
        }

        if self.inputMinPixelWidth.valueDidChange,
           let minPixelWidth = self.inputMinPixelWidth.value
        {
            self.material.set("minPixelWidth", minPixelWidth)
            shouldOutput = true
        }

        return shouldOutput
    }

    private static func modeValue(from value: String?) -> Float
    {
        switch value
        {
        case "Billboard": return 1.0
        case "Perspective Min Width": return 2.0
        default: return 0.0
        }
    }
}
